document.addEventListener('DOMContentLoaded', function () {
  var prefersDark = window.matchMedia('(prefers-color-scheme: dark)');
  mermaid.initialize({
    startOnLoad: false,
    securityLevel: 'strict',
    theme: prefersDark.matches ? 'dark' : 'default'
  });

  var mermaidCache = new Map();
  var lastMarkdown = '';
  // The version being compared against, or null when the page is not showing
  // changes, so a theme change redraws whichever of the two is on screen.
  var lastBaseline = null;

  prefersDark.addEventListener('change', function (e) {
    mermaid.initialize({
      startOnLoad: false,
      securityLevel: 'strict',
      theme: e.matches ? 'dark' : 'default'
    });
    mermaidCache.clear();
    if (lastBaseline === null) {
      renderMarkdown(lastMarkdown);
    } else {
      renderDiff(lastBaseline, lastMarkdown);
    }
  });

  // GitHub-style heading slug generator
  function githubSlug(text) {
    return text
      .toLowerCase()
      .replace(/<[^>]*>/g, '')
      .replace(/[^\p{L}\p{N}\s-]/gu, '')
      .replace(/\s+/g, '-')
      .replace(/-+/g, '-')
      .replace(/^-|-$/g, '');
  }

  function markdownitHeadingAnchor(md) {
    md.core.ruler.push('heading_anchor', function (state) {
      var slugCounts = {};
      var tokens = state.tokens;
      for (var i = 0; i < tokens.length; i++) {
        if (tokens[i].type !== 'heading_open') continue;
        var inline = tokens[i + 1];
        if (!inline || inline.type !== 'inline') continue;

        var slug = githubSlug(inline.content);
        if (!slug) continue;

        if (slugCounts[slug] !== undefined) {
          slugCounts[slug]++;
          slug = slug + '-' + slugCounts[slug];
        } else {
          slugCounts[slug] = 0;
        }

        tokens[i].attrSet('id', slug);
      }
    });
  }

  var autoDetectCache = new Map();

  var md = window.markdownit({
    html: true,
    linkify: true,
    typographer: true,
    breaks: false,
    highlight: function (str, lang) {
      if (lang && window.hljs && hljs.getLanguage(lang)) {
        try { return hljs.highlight(str, { language: lang }).value; } catch (_) {}
      }
      if (window.hljs) {
        if (autoDetectCache.has(str)) {
          return autoDetectCache.get(str);
        }
        try {
          var result = hljs.highlightAuto(str, ['javascript', 'python', 'swift', 'bash', 'json', 'html', 'css', 'typescript', 'yaml']).value;
          if (autoDetectCache.size > 200) {
            autoDetectCache.clear();
          }
          autoDetectCache.set(str, result);
          return result;
        } catch (_) {}
      }
      return '';
    }
  });

  // Stamps every top-level block with the markdown line it came from, which is
  // what scroll syncing maps editor position onto.
  function markdownitSourceLines(md) {
    md.core.ruler.push('source_lines', function (state) {
      var tokens = state.tokens;
      for (var i = 0; i < tokens.length; i++) {
        var token = tokens[i];
        if (!token.map) continue;
        if (token.nesting === 1 ||
            token.type === 'fence' ||
            token.type === 'code_block' ||
            token.type === 'hr' ||
            token.type === 'html_block') {
          token.attrSet('data-source-line', String(token.map[0]));
        }
      }
    });
  }

  md.use(markdownitHeadingAnchor);
  md.use(markdownitSourceLines);

  if (window.markdownitTaskLists) {
    md.use(window.markdownitTaskLists, { enabled: false, label: true, labelAfter: true });
  }

  if (window.markdownitEmoji) {
    md.use(window.markdownitEmoji);
  }

  function renderMermaidBlocks() {
    var blocks = Array.from(document.querySelectorAll('pre code.language-mermaid'));
    var toRender = [];
    for (var i = 0; i < blocks.length; i++) {
      var block = blocks[i];
      var src = block.textContent || '';
      var parentPre = block.closest('pre');
      if (!parentPre) {
        continue;
      }

      var holder = document.createElement('div');
      holder.dataset.mermaidSrc = src;
      // Carry the source line across, or the diagram becomes a hole in the
      // line map that scroll syncing interpolates over.
      var sourceLine = parentPre.getAttribute('data-source-line');
      if (sourceLine !== null) {
        holder.setAttribute('data-source-line', sourceLine);
      }
      if (mermaidCache.has(src)) {
        holder.innerHTML = mermaidCache.get(src);
      } else {
        holder.className = 'mermaid';
        holder.textContent = src;
        toRender.push(holder);
      }
      parentPre.replaceWith(holder);
    }

    if (toRender.length === 0) {
      return Promise.resolve();
    }

    return mermaid.run({ querySelector: '.mermaid' }).then(function () {
      for (var j = 0; j < toRender.length; j++) {
        var rendered = toRender[j];
        mermaidCache.set(rendered.dataset.mermaidSrc, rendered.innerHTML);
      }
    }).catch(function (err) {
      console.error('Mermaid render failed:', err);
    });
  }

  function renderMath() {
    if (!window.renderMathInElement) {
      return;
    }
    window.renderMathInElement(document.getElementById('content'), {
      delimiters: [
        { left: '$$', right: '$$', display: true },
        { left: '$', right: '$', display: false },
        { left: '\\(', right: '\\)', display: false },
        { left: '\\[', right: '\\]', display: true }
      ],
      throwOnError: false
    });
  }

  // Suppresses the scroll events our own scrolling produces, so a sync coming
  // from the editor is not echoed straight back at it.
  var suppressScrollReportUntil = 0;

  function scrollWithoutReporting(y) {
    suppressScrollReportUntil = Date.now() + 100;
    window.scrollTo(0, y);
  }

  var SANITIZE_OPTIONS = {
    ADD_TAGS: ['details', 'summary'],
    ADD_ATTR: ['open', 'id'],
    FORBID_TAGS: ['script', 'style', 'iframe', 'object', 'embed', 'form'],
    FORBID_ATTR: ['onerror', 'onclick', 'onload', 'onmouseover']
  };

  // Rendered, sanitised HTML for a document, or null when DOMPurify is missing —
  // in which case no rendered markup may be shown at all.
  function toSafeHTML(markdown) {
    if (!window.DOMPurify) return null;
    return DOMPurify.sanitize(md.render(markdown || ''), SANITIZE_OPTIONS);
  }

  // The scroll position is restored twice because Mermaid resolves later and
  // changes the document height when it does.
  function finishRender(scrollY) {
    renderMath();
    scrollWithoutReporting(scrollY);
    return renderMermaidBlocks().then(function () {
      scrollWithoutReporting(scrollY);
    });
  }

  function renderMarkdown(markdown) {
    lastMarkdown = markdown || '';
    lastBaseline = null;

    var content = document.getElementById('content');
    content.classList.remove('diff-mode');
    clearChanges();

    var html = toSafeHTML(lastMarkdown);
    if (html === null) {
      content.textContent = lastMarkdown;
      return;
    }

    var y = window.scrollY;
    content.innerHTML = html;
    finishRender(y);
  }

  // Renders `markdown` as a revision of `baseline`: one document with the
  // changes marked up in place, rather than two documents to compare by eye.
  function renderDiff(baseline, markdown) {
    lastBaseline = baseline || '';
    lastMarkdown = markdown || '';

    var baselineHTML = toSafeHTML(lastBaseline);
    var currentHTML = toSafeHTML(lastMarkdown);
    if (baselineHTML === null || currentHTML === null || !window.MarkdownDiff) {
      renderMarkdown(markdown);
      return;
    }

    var before = document.createElement('div');
    before.innerHTML = baselineHTML;
    var after = document.createElement('div');
    after.innerHTML = currentHTML;

    var content = document.getElementById('content');
    var y = window.scrollY;
    content.classList.add('diff-mode');
    content.innerHTML = '';
    content.appendChild(window.MarkdownDiff.merge(before, after));

    clearChanges();
    var summary = refreshChanges();
    // Diagrams resolve later and move everything below them, so the ruler is
    // measured again once they have.
    finishRender(y).then(refreshChanges);
    return summary;
  }

  window.renderMarkdown = renderMarkdown;
  window.renderDiff = renderDiff;
  renderMarkdown('');

  // --- Scroll sync ---

  function sourceLineAnchors() {
    var els = document.querySelectorAll('#content [data-source-line]');
    var anchors = [];
    for (var i = 0; i < els.length; i++) {
      anchors.push({
        line: parseInt(els[i].getAttribute('data-source-line'), 10),
        top: els[i].getBoundingClientRect().top + window.scrollY
      });
    }
    return anchors;
  }

  // Blocks cover ranges of lines, so both directions interpolate between the
  // anchors on either side instead of snapping to the nearest block.
  window.scrollToSourceLine = function (line) {
    var anchors = sourceLineAnchors();
    if (anchors.length === 0) return;

    var prev = null;
    var next = null;
    for (var i = 0; i < anchors.length; i++) {
      if (anchors[i].line <= line) {
        prev = anchors[i];
      } else {
        next = anchors[i];
        break;
      }
    }

    if (!prev) {
      scrollWithoutReporting(0);
      return;
    }

    var y = prev.top;
    if (next && next.line > prev.line) {
      var ratio = (line - prev.line) / (next.line - prev.line);
      y = prev.top + (next.top - prev.top) * ratio;
    }
    scrollWithoutReporting(y);
  };

  window.currentSourceLine = function () {
    var anchors = sourceLineAnchors();
    if (anchors.length === 0) return 0;

    var y = window.scrollY;
    var prev = null;
    var next = null;
    for (var i = 0; i < anchors.length; i++) {
      if (anchors[i].top <= y + 1) {
        prev = anchors[i];
      } else {
        next = anchors[i];
        break;
      }
    }

    if (!prev) return 0;
    if (!next || next.top <= prev.top) return prev.line;

    var ratio = (y - prev.top) / (next.top - prev.top);
    return Math.round(prev.line + (next.line - prev.line) * ratio);
  };

  var scrollReportPending = false;
  window.addEventListener('scroll', function () {
    if (Date.now() < suppressScrollReportUntil) return;
    if (scrollReportPending) return;
    if (!window.webkit || !window.webkit.messageHandlers ||
        !window.webkit.messageHandlers.previewScrolled) return;

    scrollReportPending = true;
    window.requestAnimationFrame(function () {
      scrollReportPending = false;
      window.webkit.messageHandlers.previewScrolled.postMessage(window.currentSourceLine());
    });
  });

  // --- Find in preview ---
  var _findMatches = [];
  var _findCurrentIndex = -1;

  function clearFindHighlights() {
    var marks = document.querySelectorAll('mark.search-highlight');
    for (var i = 0; i < marks.length; i++) {
      var parent = marks[i].parentNode;
      parent.replaceChild(document.createTextNode(marks[i].textContent), marks[i]);
      parent.normalize();
    }
    _findMatches = [];
    _findCurrentIndex = -1;
  }

  function getMatchesInText(text, query, useRegex) {
    var matches = [];
    if (useRegex) {
      try {
        var re = new RegExp(query, 'gi');
        var m;
        while ((m = re.exec(text)) !== null) {
          matches.push({ idx: m.index, len: m[0].length });
          if (m[0].length === 0) re.lastIndex++;
        }
      } catch (e) { /* invalid regex */ }
    } else {
      var qLower = query.toLowerCase();
      var tLower = text.toLowerCase();
      var idx = tLower.indexOf(qLower);
      while (idx !== -1) {
        matches.push({ idx: idx, len: query.length });
        idx = tLower.indexOf(qLower, idx + query.length);
      }
    }
    return matches;
  }

  function findInPreview(query, useRegex) {
    clearFindHighlights();
    if (!query) return { count: 0, current: 0 };

    var content = document.getElementById('content');
    var walker = document.createTreeWalker(content, NodeFilter.SHOW_TEXT, null);
    var textNodes = [];
    while (walker.nextNode()) {
      var nd = walker.currentNode;
      if (!(nd.parentElement && nd.parentElement.closest('svg'))) textNodes.push(nd);
    }

    for (var n = 0; n < textNodes.length; n++) {
      var node = textNodes[n];
      var text = node.textContent;
      var nodeMatches = getMatchesInText(text, query, useRegex);
      if (nodeMatches.length === 0) continue;

      var frag = document.createDocumentFragment();
      var last = 0;

      for (var i = 0; i < nodeMatches.length; i++) {
        var m = nodeMatches[i];
        if (m.idx > last) frag.appendChild(document.createTextNode(text.substring(last, m.idx)));
        var mark = document.createElement('mark');
        mark.className = 'search-highlight';
        mark.textContent = text.substring(m.idx, m.idx + m.len);
        frag.appendChild(mark);
        last = m.idx + m.len;
      }

      if (last < text.length) frag.appendChild(document.createTextNode(text.substring(last)));
      node.parentNode.replaceChild(frag, node);
    }

    _findMatches = Array.from(document.querySelectorAll('mark.search-highlight'));
    _findCurrentIndex = -1;

    if (_findMatches.length > 0) return scrollToFindMatch(0);
    return { count: 0, current: 0 };
  }

  function scrollToFindMatch(index) {
    if (_findMatches.length === 0) return { count: 0, current: 0 };
    if (_findCurrentIndex >= 0 && _findCurrentIndex < _findMatches.length) {
      _findMatches[_findCurrentIndex].classList.remove('search-highlight-current');
    }
    _findCurrentIndex = index;
    _findMatches[_findCurrentIndex].classList.add('search-highlight-current');
    _findMatches[_findCurrentIndex].scrollIntoView({ block: 'center', behavior: 'smooth' });
    return { count: _findMatches.length, current: _findCurrentIndex + 1 };
  }

  function findNextMatch() {
    if (_findMatches.length === 0) return { count: 0, current: 0 };
    return scrollToFindMatch((_findCurrentIndex + 1) % _findMatches.length);
  }

  function findPreviousMatch() {
    if (_findMatches.length === 0) return { count: 0, current: 0 };
    return scrollToFindMatch((_findCurrentIndex - 1 + _findMatches.length) % _findMatches.length);
  }

  // --- Typography ---
  // The app sets these from Settings; leaving either blank restores the
  // stylesheet's own default rather than writing an empty value.
  window.setTypography = function (family, sizePx) {
    var root = document.documentElement;
    if (family) {
      root.style.setProperty('--body-font', family);
    } else {
      root.style.removeProperty('--body-font');
    }
    if (sizePx) {
      root.style.setProperty('--body-size', sizePx + 'px');
    } else {
      root.style.removeProperty('--body-size');
    }
  };

  // --- Content width toggle ---
  window.setFullWidth = function(enabled) {
    var content = document.getElementById('content');
    if (enabled) {
      content.classList.add('full-width');
    } else {
      content.classList.remove('full-width');
    }
  };

  window.findInPreview = findInPreview;
  window.findNextMatch = findNextMatch;
  window.findPreviousMatch = findPreviousMatch;
  window.clearFindHighlights = clearFindHighlights;

  // --- Moving between changes ---
  //
  // A change is a contiguous run of marked blocks — the unit git calls a hunk.
  // Consecutive marked siblings count as one stop, so a removed paragraph and
  // the one that replaced it do not ask to be visited twice.

  var _changes = [];
  var _currentChange = -1;
  var _ruler = null;

  function diffClasses() {
    return window.MarkdownDiff.classes;
  }

  function collectChanges() {
    var blockClass = diffClasses().block;
    var children = document.getElementById('content').children;
    var groups = [];
    var run = null;

    for (var i = 0; i < children.length; i++) {
      if (children[i].classList.contains(blockClass)) {
        if (!run) {
          run = [];
          groups.push(run);
        }
        run.push(children[i]);
      } else {
        run = null;
      }
    }
    return groups;
  }

  // A run holding both a removal and the addition that replaced it reads as a
  // revision, not as two things, and is coloured like one.
  function changeKind(group) {
    var classes = diffClasses();
    var added = false;
    var removed = false;
    var changed = false;

    for (var i = 0; i < group.length; i++) {
      if (group[i].classList.contains(classes.added)) added = true;
      if (group[i].classList.contains(classes.removed)) removed = true;
      if (group[i].classList.contains(classes.changed)) changed = true;
    }

    if (changed || (added && removed)) return 'changed';
    return added ? 'added' : 'removed';
  }

  function clearCurrentChange() {
    var marked = document.querySelectorAll('.diff-change-current');
    for (var i = 0; i < marked.length; i++) {
      marked[i].classList.remove('diff-change-current');
    }
  }

  function scrollToChange(index) {
    if (_changes.length === 0) return { count: 0, current: 0 };

    clearCurrentChange();
    var count = _changes.length;
    _currentChange = ((index % count) + count) % count;

    var group = _changes[_currentChange];
    for (var i = 0; i < group.length; i++) {
      group[i].classList.add('diff-change-current');
    }
    group[0].scrollIntoView({ block: 'center', behavior: 'smooth' });

    markCurrentTick();
    return { count: count, current: _currentChange + 1 };
  }

  function nextChange() {
    if (_changes.length === 0) return { count: 0, current: 0 };
    return scrollToChange(_currentChange + 1);
  }

  function previousChange() {
    if (_changes.length === 0) return { count: 0, current: 0 };
    // From nowhere, back is the last one rather than the first.
    return scrollToChange(_currentChange <= 0 ? _changes.length - 1 : _currentChange - 1);
  }

  // --- Overview ruler ---
  //
  // One tick per change at its position down the document, so a long file shows
  // where the edits are without being scrolled through.

  function rulerElement() {
    if (!_ruler) {
      _ruler = document.createElement('div');
      _ruler.id = 'diff-ruler';
      _ruler.addEventListener('click', function (event) {
        var index = event.target && event.target.getAttribute('data-change-index');
        if (index !== null && index !== undefined) {
          scrollToChange(parseInt(index, 10));
        }
      });
      document.body.appendChild(_ruler);
    }
    return _ruler;
  }

  function renderRuler() {
    var element = rulerElement();
    element.textContent = '';

    if (_changes.length === 0) {
      element.style.display = 'none';
      return;
    }
    element.style.display = 'block';

    var documentHeight = document.documentElement.scrollHeight || 1;
    for (var i = 0; i < _changes.length; i++) {
      var group = _changes[i];
      var first = group[0].getBoundingClientRect();
      var last = group[group.length - 1].getBoundingClientRect();
      var top = first.top + window.scrollY;
      var height = (last.top + window.scrollY + last.height) - top;

      var tick = document.createElement('div');
      tick.className = 'diff-ruler-tick diff-ruler-' + changeKind(group);
      tick.style.top = (top / documentHeight * 100) + '%';
      tick.style.height = (height / documentHeight * 100) + '%';
      tick.setAttribute('data-change-index', String(i));
      element.appendChild(tick);
    }
    markCurrentTick();
  }

  function markCurrentTick() {
    if (!_ruler) return;
    var ticks = _ruler.children;
    for (var i = 0; i < ticks.length; i++) {
      if (i === _currentChange) {
        ticks[i].classList.add('current');
      } else {
        ticks[i].classList.remove('current');
      }
    }
  }

  function refreshChanges() {
    _changes = collectChanges();
    if (_currentChange >= _changes.length) _currentChange = -1;
    renderRuler();
    return { count: _changes.length, current: _currentChange + 1 };
  }

  function clearChanges() {
    _changes = [];
    _currentChange = -1;
    clearCurrentChange();
    if (_ruler) {
      _ruler.textContent = '';
      _ruler.style.display = 'none';
    }
  }

  // Ticks are placed as a fraction of the document, and both the fraction and
  // the document change when the pane is resized.
  var rulerRefreshPending = false;
  window.addEventListener('resize', function () {
    if (_changes.length === 0 || rulerRefreshPending) return;
    rulerRefreshPending = true;
    window.requestAnimationFrame(function () {
      rulerRefreshPending = false;
      renderRuler();
    });
  });

  window.nextChange = nextChange;
  window.previousChange = previousChange;
  window.scrollToChange = scrollToChange;
  window.changeSummary = function () {
    return { count: _changes.length, current: _currentChange + 1 };
  };

  // Intercept link clicks and delegate to native app
  document.addEventListener('click', function (e) {
    var target = e.target;
    while (target && target.tagName !== 'A') {
      target = target.parentElement;
    }
    if (target && target.tagName === 'A') {
      var href = target.getAttribute('href');
      if (href && href.charAt(0) === '#') {
        e.preventDefault();
        var id = decodeURIComponent(href.substring(1));
        var el = document.getElementById(id);
        if (el) el.scrollIntoView({ behavior: 'smooth' });
      } else if (href) {
        e.preventDefault();
        e.stopPropagation();
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.linkClicked) {
          window.webkit.messageHandlers.linkClicked.postMessage(href);
        }
      }
    }
  });
});
