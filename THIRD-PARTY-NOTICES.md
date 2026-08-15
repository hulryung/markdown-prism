# Third-Party Notices

Markdown Prism renders offline, which it does by shipping the parser, the
highlighter, the maths typesetter and the diagram renderer inside the app rather
than fetching them. Those libraries are redistributed under their own licences,
reproduced or linked below. They live in
`Sources/MarkdownPrism/Resources/vendor/` and are loaded by the two preview
shells.

Licences were read from the shipped files themselves, or from the upstream
package at the exact version shipped, rather than assumed.

| Library | Version | Licence |
|---|---|---|
| [markdown-it](https://github.com/markdown-it/markdown-it) | 14.1.0 | MIT |
| [markdown-it-emoji](https://github.com/markdown-it/markdown-it-emoji) | 3.0.0 | MIT |
| [markdown-it-task-lists](https://github.com/revin/markdown-it-task-lists) | 2.1.1 [^1] | ISC |
| [highlight.js](https://github.com/highlightjs/highlight.js) | 11.9.0 | BSD-3-Clause |
| [KaTeX](https://github.com/KaTeX/KaTeX) | 0.16.11 | MIT |
| [Mermaid](https://github.com/mermaid-js/mermaid) | 11.12.0 | MIT |
| [DOMPurify](https://github.com/cure53/DOMPurify) | 3.3.3 | Apache-2.0 OR MPL-2.0 |

The `github.min.css` and `github-dark.min.css` themes are part of highlight.js
and carry its licence. The `KaTeX_*.woff2` faces are part of KaTeX and carry
its licence.

Mermaid bundles its own copy of DOMPurify (3.2.6), so that licence applies to
the app twice over: once for the copy the preview loads directly, once for the
copy inside Mermaid.

[^1]: The package fetched was 2.1.1; the banner inside the file it ships still
says 2.1.0. Recorded as fetched, with the discrepancy noted rather than
silently resolved either way.

---

## MIT — markdown-it, markdown-it-emoji, KaTeX, Mermaid

> Copyright (c) 2014 Vitaly Puzrin, Alex Kocharin (markdown-it)  
> Copyright (c) 2014 Vitaly Puzrin (markdown-it-emoji)  
> Copyright (c) 2013-2020 Khan Academy and other contributors (KaTeX)  
> Copyright (c) 2014 - 2022 Knut Sveidqvist (Mermaid)
>
> Permission is hereby granted, free of charge, to any person obtaining a copy
> of this software and associated documentation files (the "Software"), to deal
> in the Software without restriction, including without limitation the rights
> to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
> copies of the Software, and to permit persons to whom the Software is
> furnished to do so, subject to the following conditions:
>
> The above copyright notice and this permission notice shall be included in
> all copies or substantial portions of the Software.
>
> THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
> IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
> FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
> AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
> LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
> OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
> THE SOFTWARE.

## ISC — markdown-it-task-lists

> Copyright (c) 2016, Revin Guillen
>
> Permission to use, copy, modify, and/or distribute this software for any
> purpose with or without fee is hereby granted, provided that the above
> copyright notice and this permission notice appear in all copies.
>
> THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
> REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
> AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
> INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
> LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
> OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
> PERFORMANCE OF THIS SOFTWARE.

## BSD-3-Clause — highlight.js

> Copyright (c) 2006, Ivan Sagalaev. All rights reserved.
>
> Redistribution and use in source and binary forms, with or without
> modification, are permitted provided that the following conditions are met:
>
> * Redistributions of source code must retain the above copyright notice, this
>   list of conditions and the following disclaimer.
> * Redistributions in binary form must reproduce the above copyright notice,
>   this list of conditions and the following disclaimer in the documentation
>   and/or other materials provided with the distribution.
> * Neither the name of the copyright holder nor the names of its contributors
>   may be used to endorse or promote products derived from this software
>   without specific prior written permission.
>
> THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
> AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
> IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
> ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
> LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
> CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
> SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
> INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
> CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
> ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
> POSSIBILITY OF SUCH DAMAGE.

## Apache-2.0 OR MPL-2.0 — DOMPurify

Copyright (c) Cure53 and other contributors. DOMPurify is dual licensed: you may
use it under the terms of either the Apache License 2.0 or the Mozilla Public
License 2.0.

- Apache License 2.0: https://www.apache.org/licenses/LICENSE-2.0
- Mozilla Public License 2.0: https://www.mozilla.org/MPL/2.0/
- As shipped: https://github.com/cure53/DOMPurify/blob/3.3.3/LICENSE
