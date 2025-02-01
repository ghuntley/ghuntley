cheddar
=======

Cheddar is a tiny Rust tool that uses [syntect][] to render source code to
syntax-highlighted HTML.

It's invocation is compatible with `cgit` filters, i.e. data is read from
`stdin` and the filename is taken from `argv`:

```shell
cat README.md | cheddar README.md > README.html

```

In fact, if you are looking at this file on git.tazj.in chances are that it was
rendered by cheddar.

The name was chosen because I was eyeing a pack of cheddar-flavoured crisps
while thinking about name selection.

[syntect]: https://github.com/trishume/syntect
