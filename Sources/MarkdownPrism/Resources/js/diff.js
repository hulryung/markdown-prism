/* Rich diff for rendered Markdown.
 *
 * Both versions of a document are rendered to HTML first, and the difference is
 * taken over the resulting elements rather than over the Markdown source. That
 * is what lets the result stay a readable document — a changed sentence keeps
 * its heading, its list, its emphasis — instead of a wall of +/- lines.
 *
 * The comparison runs at three granularities, each falling out of the one above:
 *
 *   1. Blocks. Top-level elements are matched by their serialised form. What
 *      survives is unchanged; the rest is a run of removals and additions.
 *   2. Containers. A removed/added pair that is the same kind of element and
 *      reads as a revision of the same thing recurses, so editing one list item
 *      marks that item rather than replacing the whole list.
 *   3. Words. A pair with no block children is diffed word by word, and the
 *      differences come out as inline <ins>/<del>.
 *
 * Loaded by both preview shells; `preview.js` drives it.
 */
(function (global) {
  'use strict';

  /* What a marked block is called. Kept in one place because the page also
     navigates by these — `preview.js` walks them for next/previous change and
     for the overview ruler — and two copies of a class name drift. */
  var CLASSES = {
    block: 'diff-block',
    added: 'diff-block-added',
    removed: 'diff-block-removed',
    changed: 'diff-block-changed'
  };

  /* Elements that stand on their own. Diffing inside a code fence or an image
     produces noise rather than insight, and a Mermaid source block only renders
     if it reaches the renderer intact. */
  var ATOMIC = { PRE: 1, IMG: 1, HR: 1, SVG: 1, VIDEO: 1, IFRAME: 1 };

  /* Tags that make their parent a container worth recursing into, rather than
     something to diff as a run of words. */
  var BLOCK = {
    P: 1, DIV: 1, UL: 1, OL: 1, LI: 1, PRE: 1, BLOCKQUOTE: 1, TABLE: 1,
    THEAD: 1, TBODY: 1, TFOOT: 1, TR: 1, TD: 1, TH: 1, DL: 1, DT: 1, DD: 1,
    H1: 1, H2: 1, H3: 1, H4: 1, H5: 1, H6: 1, HR: 1, DETAILS: 1, SECTION: 1
  };

  /* A pair less alike than this is two different blocks, not one rewritten. */
  var SIMILARITY_THRESHOLD = 0.4;

  /* Deep enough for a table cell inside a row inside a table inside a list. */
  var MAX_DEPTH = 6;

  /* The quadratic table is the expensive part; past this it is cheaper, and no
     less honest, to call the region wholly replaced. */
  var MAX_CELLS = 2000000;

  /* Math is delimited by characters the word diff would happily split across an
     <ins> boundary, leaving KaTeX with an unterminated expression. Blocks
     carrying any are replaced whole instead of refined. */
  var MATH_DELIMITERS = /\$|\\\(|\\\[/;

  // --- Sequence comparison ---

  /* Longest common subsequence, as a list of {type, oldIndex, newIndex} steps.
     Comparison is by identity on the array's own values, so callers pass
     strings they have already reduced their objects to. */
  function diffSequences(a, b) {
    var n = a.length;
    var m = b.length;
    var ops = [];
    var i;

    // Matching heads and tails are the common case and cost nothing to peel off,
    // which keeps the table small for a document with a few edits in it.
    var start = 0;
    while (start < n && start < m && a[start] === b[start]) start++;

    var endA = n;
    var endB = m;
    while (endA > start && endB > start && a[endA - 1] === b[endB - 1]) {
      endA--;
      endB--;
    }

    for (i = 0; i < start; i++) {
      ops.push({ type: 'equal', oldIndex: i, newIndex: i });
    }

    var spanA = endA - start;
    var spanB = endB - start;

    if (spanA === 0 || spanB === 0 || spanA * spanB > MAX_CELLS) {
      for (i = start; i < endA; i++) ops.push({ type: 'delete', oldIndex: i });
      for (i = start; i < endB; i++) ops.push({ type: 'insert', newIndex: i });
    } else {
      var stride = spanB + 1;
      var table = new Int32Array((spanA + 1) * stride);

      for (var x = spanA - 1; x >= 0; x--) {
        for (var y = spanB - 1; y >= 0; y--) {
          if (a[start + x] === b[start + y]) {
            table[x * stride + y] = table[(x + 1) * stride + (y + 1)] + 1;
          } else {
            var down = table[(x + 1) * stride + y];
            var right = table[x * stride + (y + 1)];
            table[x * stride + y] = down >= right ? down : right;
          }
        }
      }

      var p = 0;
      var q = 0;
      while (p < spanA && q < spanB) {
        if (a[start + p] === b[start + q]) {
          ops.push({ type: 'equal', oldIndex: start + p, newIndex: start + q });
          p++;
          q++;
        } else if (table[(p + 1) * stride + q] >= table[p * stride + (q + 1)]) {
          ops.push({ type: 'delete', oldIndex: start + p });
          p++;
        } else {
          ops.push({ type: 'insert', newIndex: start + q });
          q++;
        }
      }
      while (p < spanA) { ops.push({ type: 'delete', oldIndex: start + p }); p++; }
      while (q < spanB) { ops.push({ type: 'insert', newIndex: start + q }); q++; }
    }

    for (i = endA; i < n; i++) {
      ops.push({ type: 'equal', oldIndex: i, newIndex: endB + (i - endA) });
    }
    return ops;
  }

  // --- Blocks ---

  /* What two elements are compared by. Source lines are stripped: a block that
     only moved down the document is still the same block. */
  function signature(element) {
    return element.outerHTML.replace(/ data-source-line="[^"]*"/g, '');
  }

  function elementChildren(element) {
    var result = [];
    var children = element.children;
    for (var i = 0; i < children.length; i++) result.push(children[i]);
    return result;
  }

  function mergeChildren(oldElements, newElements, depth) {
    var oldKeys = oldElements.map(signature);
    var newKeys = newElements.map(signature);
    var ops = diffSequences(oldKeys, newKeys);
    var fragment = document.createDocumentFragment();

    var i = 0;
    while (i < ops.length) {
      if (ops[i].type === 'equal') {
        fragment.appendChild(newElements[ops[i].newIndex].cloneNode(true));
        i++;
        continue;
      }

      // One changed region: every removal and every addition between two
      // surviving blocks, in whichever order the walk produced them.
      var removed = [];
      var added = [];
      while (i < ops.length && ops[i].type !== 'equal') {
        if (ops[i].type === 'delete') {
          removed.push(oldElements[ops[i].oldIndex]);
        } else {
          added.push(newElements[ops[i].newIndex]);
        }
        i++;
      }
      appendChangedRegion(fragment, removed, added, depth);
    }

    return fragment;
  }

  function appendChangedRegion(fragment, removed, added, depth) {
    var paired = Math.min(removed.length, added.length);
    var i;

    for (i = 0; i < paired; i++) {
      var refined = refine(removed[i], added[i], depth);
      if (refined) {
        fragment.appendChild(refined);
      } else {
        fragment.appendChild(mark(removed[i].cloneNode(true), 'removed'));
        fragment.appendChild(mark(added[i].cloneNode(true), 'added'));
      }
    }

    for (i = paired; i < removed.length; i++) {
      fragment.appendChild(mark(removed[i].cloneNode(true), 'removed'));
    }
    for (i = paired; i < added.length; i++) {
      fragment.appendChild(mark(added[i].cloneNode(true), 'added'));
    }
  }

  /* One element showing how `oldElement` became `newElement`, or null when the
     two are too far apart to be worth reading as a single revision. */
  function refine(oldElement, newElement, depth) {
    if (depth >= MAX_DEPTH) return null;
    if (oldElement.tagName !== newElement.tagName) return null;
    if (ATOMIC[oldElement.tagName]) return null;
    if (similarity(oldElement, newElement) < SIMILARITY_THRESHOLD) return null;

    var shell = newElement.cloneNode(false);

    if (hasBlockChildren(oldElement) || hasBlockChildren(newElement)) {
      shell.appendChild(
        mergeChildren(elementChildren(oldElement), elementChildren(newElement), depth + 1)
      );
      shell.classList.add(CLASSES.block, CLASSES.changed);
      return shell;
    }

    if (MATH_DELIMITERS.test(oldElement.textContent) ||
        MATH_DELIMITERS.test(newElement.textContent)) {
      return null;
    }

    shell.innerHTML = mergeWords(oldElement.innerHTML, newElement.innerHTML);
    shell.classList.add(CLASSES.block, CLASSES.changed);
    return shell;
  }

  function hasBlockChildren(element) {
    var children = element.children;
    for (var i = 0; i < children.length; i++) {
      if (BLOCK[children[i].tagName]) return true;
    }
    return false;
  }

  /* Dice coefficient over words: how much of the two blocks is the same text,
     regardless of where in the block it sits. */
  function similarity(oldElement, newElement) {
    var a = wordsOf(oldElement.textContent);
    var b = wordsOf(newElement.textContent);
    if (a.length === 0 && b.length === 0) return 1;
    if (a.length === 0 || b.length === 0) return 0;

    var counts = Object.create(null);
    var i;
    for (i = 0; i < a.length; i++) {
      counts[a[i]] = (counts[a[i]] || 0) + 1;
    }
    var shared = 0;
    for (i = 0; i < b.length; i++) {
      if (counts[b[i]] > 0) {
        counts[b[i]]--;
        shared++;
      }
    }
    return (2 * shared) / (a.length + b.length);
  }

  function wordsOf(text) {
    var trimmed = String(text || '').trim();
    return trimmed ? trimmed.split(/\s+/) : [];
  }

  /* Marks a whole block as added or removed, and drops the source lines from
     removals: they name lines in a document that no longer exists, and scroll
     sync interpolates between whatever anchors it finds. */
  function mark(element, kind) {
    element.classList.add(CLASSES.block, kind === 'added' ? CLASSES.added : CLASSES.removed);
    if (kind === 'removed') {
      element.removeAttribute('data-source-line');
      var nested = element.querySelectorAll('[data-source-line]');
      for (var i = 0; i < nested.length; i++) {
        nested[i].removeAttribute('data-source-line');
      }
    }
    return element;
  }

  // --- Words ---

  /* Splits markup into tags, runs of whitespace, words, and single punctuation
     marks, so that a tag is never broken across a difference.
   *
   * Punctuation is its own token on purpose. Left attached, "receipts" and
   * "receipts," are unequal, and adding one comma mid-sentence makes every
   * following clause look rewritten. The word classes are Unicode-aware, so
   * this splits Korean and accented text the same way it splits English. */
  function tokenize(html) {
    return String(html || '').match(/<[^>]*>|\s+|[\p{L}\p{N}_'’-]+|[^\s<]/gu) || [];
  }

  function isTag(token) {
    return token.charAt(0) === '<';
  }

  /* The markup of `newHTML` with the words that changed marked up inline.
   *
   * Only the surviving and added tokens carry tags, and together they are
   * exactly `newHTML` — so the result is always balanced. Removed text is
   * re-inserted as bare words inside <del>, and removed tags are dropped, which
   * is what keeps that guarantee.
   */
  function mergeWords(oldHTML, newHTML) {
    var a = tokenize(oldHTML);
    var b = tokenize(newHTML);
    var ops = diffSequences(a, b);
    var out = '';

    var i = 0;
    while (i < ops.length) {
      if (ops[i].type === 'equal') {
        out += b[ops[i].newIndex];
        i++;
        continue;
      }

      var removed = [];
      var added = [];
      while (i < ops.length && ops[i].type !== 'equal') {
        if (ops[i].type === 'delete') {
          removed.push(a[ops[i].oldIndex]);
        } else {
          added.push(b[ops[i].newIndex]);
        }
        i++;
      }

      out += removedMarkup(removed);
      out += addedMarkup(added);
    }
    return out;
  }

  function removedMarkup(tokens) {
    var text = '';
    for (var i = 0; i < tokens.length; i++) {
      if (!isTag(tokens[i])) text += tokens[i];
    }
    // Trimmed because whitespace around a removal belonged to the old text, and
    // the surviving text brings its own; highlighting it only makes the marker
    // look like it swallowed the neighbouring space.
    var trimmed = text.trim();
    return trimmed ? '<del class="diff-words-removed">' + trimmed + '</del>' : '';
  }

  function addedMarkup(tokens) {
    var out = '';
    var pending = '';

    /* Whitespace at the edges is emitted outside the <ins>: it is part of the
       new document, so it has to survive, but highlighting it would widen the
       marker past the words that actually changed. */
    function flush() {
      if (!pending) return;
      var leading = /^\s*/.exec(pending)[0];
      var rest = pending.slice(leading.length);
      var trailing = /\s*$/.exec(rest)[0];
      var words = rest.slice(0, rest.length - trailing.length);

      out += leading;
      if (words) out += '<ins class="diff-words-added">' + words + '</ins>';
      out += trailing;
      pending = '';
    }

    for (var i = 0; i < tokens.length; i++) {
      if (isTag(tokens[i])) {
        // Wrapping across a tag would put the <ins> and its close on opposite
        // sides of an element boundary.
        flush();
        out += tokens[i];
      } else {
        pending += tokens[i];
      }
    }
    flush();
    return out;
  }

  // --- Entry point ---

  /* Merges two rendered documents into one annotated tree.
     Both arguments are elements holding rendered Markdown. */
  function merge(oldRoot, newRoot) {
    return mergeChildren(elementChildren(oldRoot), elementChildren(newRoot), 0);
  }

  global.MarkdownDiff = {
    merge: merge,
    classes: CLASSES,
    // Exposed for the renderer tests, which check these directly rather than
    // inferring them from a rendered page.
    mergeWords: mergeWords,
    diffSequences: diffSequences
  };
})(window);
