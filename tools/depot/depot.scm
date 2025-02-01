;; Copyright (c) 2019 Vincent Ambo
;; Copyright (c) 2020-2021 The TVL Authors
;; SPDX-License-Identifier: MIT

;; depot helps you build planets
;;
;; it is a tiny tool designed to ease workflows in monorepos that are
;; modeled after the tvl depot.
;;
;; users familiar with workflows from other, larger monorepos may be
;; used to having a build tool that can work in any tree location.
;; depot enables this, but with nix-y monorepos.

(import (chicken base)
        (chicken format)
        (chicken irregex)
        (chicken port)
        (chicken file)
        (chicken file posix)
        (chicken process)
        (chicken process-context)
        (chicken string)
        (matchable)
        (only (chicken io) read-string))

(define usage #<<USAGE
usage: depot <command> [<target>]

target:
  a target specification with meaning inside of the repository. can
  be absolute (starting with //) or relative to the current directory
  (as long as said directory is inside of the repo). if no target is
  specified, the current directory's physical target is built.

  for example:

    //tools/depot - absolute physical target
    //foo/bar:baz     - absolute virtual target
    depot         - relative physical target
    :baz              - relative virtual target

commands:
  build - build a target
  shell - enter a shell with the target's build dependencies
  path  - print source folder for the target
  repl  - start a nix repl in the repository root
  run   - build a target and execute its output

USAGE
)

;; parse target definitions. trailing slashes on physical targets are
;; allowed for shell autocompletion.
;;
;; component ::= any string without "/" or ":"
;;
;; physical-target ::= <component>
;;                   | <component> "/"
;;                   | <component> "/" <physical-target>
;;
;; virtual-target ::= ":" <component>
;;
;; relative-target ::= <physical-target>
;;                   | <virtual-target>
;;                   | <physical-target> <virtual-target>
;;
;; root-anchor ::= "//"
;;
;; target ::= <relative-target> | <root-anchor> <relative-target>

;; read a path component until it looks like something else is coming
(define (read-component first port)
  (let ((keep-reading?
         (lambda () (not (or (eq? #\/ (peek-char port))
                             (eq? #\: (peek-char port))
                             (eof-object? (peek-char port)))))))
    (let reader ((acc (list first))
                 (condition (keep-reading?)))
      (if condition (reader (cons (read-char port) acc) (keep-reading?))
          (list->string (reverse acc))))))

;; read something that started with a slash. what will it be?
(define (read-slash port)
  (if (eq? #\/ (peek-char port))
      (begin (read-char port)
             'root-anchor)
      'path-separator))

;; read any target token and leave port sitting at the next one
(define (read-token port)
  (match (read-char port)
         [#\/ (read-slash port)]
         [#\: 'virtual-separator]
         [other (read-component other port)]))

;; read a target into a list of target tokens
(define (read-target target-str)
  (call-with-input-string
   target-str
   (lambda (port)
     (let reader ((acc '()))
       (if (eof-object? (peek-char port))
           (reverse acc)
           (reader (cons (read-token port) acc)))))))

(define-record target absolute components virtual)
(define (empty-target) (make-target #f '() #f))

(define-record-printer (target t out)
  (fprintf out (conc (if (target-absolute t) "//" "")
                     (string-intersperse (target-components t) "/")
                     (if (target-virtual t) ":" "")
                     (or (target-virtual t) ""))))

;; parse and validate a list of target tokens
(define parse-tokens
  (lambda (tokens #!optional (mode 'root) (acc (empty-target)))
    (match (cons mode tokens)
           ;; absolute target
           [('root . ('root-anchor . rest))
            (begin (target-absolute-set! acc #t)
                   (parse-tokens rest 'root acc))]

           ;; relative target minus potential garbage
           [('root . (not ('path-separator . _)))
            (parse-tokens tokens 'normal acc)]

           ;; virtual target
           [('normal . ('virtual-separator . rest))
            (parse-tokens rest 'virtual acc)]

           [('virtual . ((? string? v)))
            (begin
              (target-virtual-set! acc v)
              acc)]

           ;; chomp through all components and separators
           [('normal . ('path-separator . rest)) (parse-tokens rest 'normal acc)]
           [('normal . ((? string? component) . rest))
            (begin (target-components-set!
                    acc (append (target-components acc) (list component)))
                   (parse-tokens rest 'normal acc ))]

           ;; nothing more to parse and not in a weird state, all done, yay!
           [('normal . ()) acc]

           ;; oh no, we ran out of input too early :(
           [(_ . ()) `(error . ,(format "unexpected end of input while parsing ~s target" mode))]

           ;; something else was invalid :(
           [_ `(error . ,(format "unexpected ~s while parsing ~s target" (car tokens) mode))])))

(define (parse-target target)
  (parse-tokens (read-target target)))

;; turn relative targets into absolute targets based on the current
;; directory
(define (normalise-target t)
  (when (not (target-absolute t))
    (target-components-set! t (append (relative-repo-path)
                                      (target-components t)))
    (target-absolute-set! t #t))
  t)

;; nix doesn't care about the distinction between physical and virtual
;; targets, normalise it away
(define (normalised-components t)
  (if (target-virtual t)
      (append (target-components t) (list (target-virtual t)))
      (target-components t)))

;; return the current repository root as a string
(define mg--repository-root #f)
(define (repository-root)
  (or mg--repository-root
      (begin
        (set! mg--repository-root
              (or (get-environment-variable "MG_ROOT")
                  (string-chomp
                   (call-with-input-pipe "git rev-parse --show-toplevel"
                                         (lambda (p) (read-string #f p))))))
        mg--repository-root)))

;; determine the current path relative to the root of the repository
;; and return it as a list of path components.
(define (relative-repo-path)
  (string-split
   (substring (current-directory) (string-length (repository-root))) "/"))

;; escape a string for interpolation in nix code
(define (nix-escape str)
  (string-translate* str '(("\"" . "\\\"")
                           ("${" . "\\${"))))

;; create a nix expression to build the attribute at the specified
;; components
;;
;; an empty target will build the current folder instead.
;;
;; this uses builtins.getAttr explicitly to avoid problems with
;; escaping.
(define (nix-expr-for target)
  (let nest ((parts (normalised-components (normalise-target target)))
             (acc (conc "(import " (repository-root) " {})")))
    (match parts
           [() (conc "with builtins; " acc)]
           [_ (nest (cdr parts)
                    (conc "(getAttr \""
                          (nix-escape (car parts))
                          "\" " acc ")"))])))

;; exit and complain at the user if something went wrong
(define (mg-error message)
  (format (current-error-port) "[depot] error: ~A~%" message)
  (exit 1))

(define (guarantee-success value)
  (match value
         [('error . message) (mg-error message)]
         [_ value]))

(define-record build-args target passthru unknown)
(define (execute-build args)
  (let ((expr (nix-expr-for (build-args-target args))))
    (fprintf (current-error-port) "[depot] building target ~A~%" (build-args-target args))
    (process-execute "nix-build" (append (list "-E" expr "--show-trace")
                                         (or (build-args-passthru args) '())))))

;; split the arguments used for builds into target/unknown args/nix
;; args, where the latter occur after '--'
(define (parse-build-args acc args)
  (match args
         ;; no arguments remaining, return accumulator as is
         [() acc]

         ;; next argument is '--' separator, split off passthru and
         ;; return
         [("--" . passthru)
          (begin
            (build-args-passthru-set! acc passthru)
            acc)]

         [(arg . rest)
          ;; set target if not already known (and if the first
          ;; argument does not look like an accidental unknown
          ;; parameter)
          (if (and (not (build-args-target acc))
                   (not (substring=? "-" arg)))
              (begin
                (build-args-target-set! acc (guarantee-success (parse-target arg)))
                (parse-build-args acc rest))

              ;; otherwise, collect unknown arguments
              (begin
                (build-args-unknown-set! acc (append (or (build-args-unknown acc) '())
                                                     (list arg)))
                (parse-build-args acc rest)))]))

;; parse the passed build args, applying sanity checks and defaulting
;; the target if necessary, then execute the build
(define (build args)
  (let ((parsed (parse-build-args (make-build-args #f #f #f) args)))
    ;; fail if there are unknown arguments present
    (when (build-args-unknown parsed)
      (let ((unknown (string-intersperse (build-args-unknown parsed))))
        (mg-error (sprintf "unknown arguments: ~a

if you meant to pass these arguments to nix, please separate them with
'--' like so:

  depot build ~a -- ~a"
                        unknown
                        (or (build-args-target parsed) "")
                        unknown))))

    ;; default the target to the current folder's main target
    (unless (build-args-target parsed)
      (build-args-target-set! parsed (empty-target)))

    (execute-build parsed)))

(define (execute-shell t)
  (let ((expr (nix-expr-for t))
        (user-shell (or (get-environment-variable "SHELL") "bash")))
    (fprintf (current-error-port) "[depot] entering shell for ~A~%" t)
    (process-execute "nix-shell"
                     (list "-E" expr "--command" user-shell))))

(define (shell args)
  (match args
         [() (execute-shell (empty-target))]
         [(arg) (execute-shell
                 (guarantee-success (parse-target arg)))]
         [other (print "not yet implemented")]))

(define (repl args)
  (process-execute "nix" (append (list "repl" "--show-trace" (repository-root)) args)))

(define (execute-run t #!optional cmd-args)
  (fprintf (current-error-port) "[depot] building target ~A~%" t)
  (let* ((expr (nix-expr-for t))
         (out (call-with-input-pipe
               (apply string-append
                      ;; TODO(sterni): temporary gc root
                      (intersperse `("nix-build" "-E" ,(qs expr) "--no-out-link")
                                   " "))
               (lambda (p)
                 (string-chomp (let ((s (read-string #f p)))
                                 (if (eq? s #!eof) "" s)))))))

    ;; TODO(sterni): can we get the exit code of nix-build somehow?
    (when (= (string-length out) 0)
      (mg-error (string-append "Couldn't build target " (format "~A" t)))
      (exit 1))

    (fprintf (current-error-port) "[depot] running target ~A~%" t)
    (process-execute
     ;; If the output is a file, we assume it's an executable à la writeExecline,
     ;; otherwise we look in the bin subdirectory and pick the only executable.
     ;; Handling multiple executables is not possible at the moment, the choice
     ;; could be made via a command line flag in the future.
     (if (regular-file? out)
         out
         (let* ((dir-path (string-append out "/bin"))
                (dir-contents (if (directory-exists? dir-path)
                                  (directory dir-path #f)
                                  '())))
           (case (length dir-contents)
             ((0) (mg-error "no executables in build output")
                  (exit 1))
             ((1) (string-append dir-path "/" (car dir-contents)))
             (else (mg-error "more than one executable in build output")
                   (exit 1)))))
     cmd-args)))

(define (run args)
  (match args
         [() (execute-run (empty-target))]
         ;; TODO(sterni): flag for selecting binary name
         [other (execute-run (guarantee-success (parse-target (car args)))
                             (cdr args))]))

(define (path args)
  (match args
         [(arg)
          (print (apply string-append
                        (intersperse
                         (cons (repository-root)
                               (target-components
                                (normalise-target
                                 (guarantee-success (parse-target arg)))))
                         "/")))]
         [() (mg-error "path command needs a target")]
         [other (mg-error (format "unknown arguments: ~a" other))]))

(define (main args)
  (match args
         [() (print usage)]
         [("build" . _) (build (cdr args))]
         [("shell" . _) (shell (cdr args))]
         [("path" . _) (path (cdr args))]
         [("repl" . _) (repl (cdr args))]
         [("run" . _) (run (cdr args))]
         [other (begin (print "unknown command: depot " args)
                       (print usage))]))

(main (command-line-arguments))
