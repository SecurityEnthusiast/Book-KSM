# License

This work is dual-licensed, because it is two different things in one repository.

The **writing** is a book: the chapters, their diagrams, the cover and this page. It is licensed
under [CC BY-NC-SA 4.0](https://creativecommons.org/licenses/by-nc-sa/4.0/).

The **lab code** is software: everything inside any `lab/` directory. It is licensed under the
[MIT License](#2-lab-code-mit), so you can take a pattern from it into your own systems without
thinking about it.

Copyright (c) 2026 Meghdad Shamsaei

---

## At a glance

| What you want to do | Writing | Lab code |
|---|---|---|
| Read it, run the labs, learn from it | Yes | Yes |
| Copy a pattern from the lab into your own project, at work | n/a | **Yes** |
| Quote a section in a blog post, talk or thesis, with credit | Yes | Yes |
| Translate it and publish the translation under the same terms | Yes | Yes |
| Use it to train engineers inside your own organisation | **Yes**, see below | Yes |
| Sell it, or run a paid course or training product built on it | **Ask first** | Yes |
| Republish it without credit, or under a more restrictive licence | No | No |

This table is a summary for orientation. The licences linked below are what actually govern.

---

## 1. The writing: CC BY-NC-SA 4.0

Covers every chapter document (`Chapter 00/Chapter 00.md` and its siblings), every diagram
inside them, the cover page and its index, the reference index, this licence page, and the cover
art in `assets/`.

In short: **share and adapt it, credit the author, do not sell it, and pass on the same
freedom.**

Full legal text: <https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode>

### What "NonCommercial" means here

`NonCommercial` is the one term in CC BY-NC-SA that people reasonably disagree about, so here is
the author's intent, offered as permission rather than as reinterpretation of the licence.

**Explicitly permitted**, and no need to ask:

- Reading it, at work or anywhere else, including at a company that makes money.
- Using it to teach your own colleagues, internally and without charge.
- Quoting from it in a talk, a post, a paper or a thesis, with credit.
- Translating it, or building teaching material from it, released under the same licence.

**Ask first.** Anything where the book itself is what is being sold or is a material part of a
paid offering: a commercial training course, a paid workshop, a book or an inclusion in a
product or subscription. Open an issue on this repository and say what you have in mind. The
answer is usually yes.

### How to credit

> "Key, PKI and Secret Management: built, not described" by Meghdad Shamsaei, licensed under
> CC BY-NC-SA 4.0. Source: `<repository URL>`

If you adapted rather than quoted, say so and say what you changed.

---

## 2. Lab code: MIT

Covers every file inside any `lab/` directory, at any depth: Dockerfiles, Compose files, shell
scripts, Python, SQL, JSON and YAML. If it runs, it is MIT.

This is deliberate. The point of the labs is that you take what you learn back to real systems,
and a copyleft or non-commercial licence on a Dockerfile would make that awkward for exactly the
people the book is written for.

```text
MIT License

Copyright (c) 2026 Meghdad Shamsaei

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

## 3. Every credential in this repository is fake

`hunter2-payments-prod`, and every other password, key and certificate in these chapters, is a
teaching prop. Chapter 01 finds that one in sixteen places; Chapter 02 retires it and shows all
sixteen copies becoming worthless without deleting any of them. It is left in the files, and in
this repository's history, on purpose, because it is an exhibit later chapters refer back to.

**Nothing here is, or has ever been, a live credential.** If a secret scanner flags this
repository, that is the scanner working correctly on material that was planted for it to find.

---

## 4. The labs build insecure systems on purpose

This is a book about how systems fail, so the labs spend most of their time in states you would
never ship. They run services as root, put passwords in world-readable files, downgrade
authentication, disable transport encryption, and stand up an impostor server to attack the
application with. Each of those is set up, measured, and then fixed within the same chapter.

Two things follow. Run the labs in the throwaway containers the book provides, not on a machine
that matters. And do not copy a snippet out of the middle of a chapter into production without
reading what the chapter goes on to say about it; the mid-chapter state is frequently the
mistake being demonstrated.

The MIT licence's warranty disclaimer above, and the equivalent in CC BY-NC-SA 4.0 section 5,
apply to all of it.
