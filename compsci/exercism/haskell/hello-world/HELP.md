# Help

## Running the tests

To run the test suite, execute the following command:

```bash
stack test
```

#### If you get an error message like this...

```
No .cabal file found in directory
```

or

```
RedownloadInvalidResponse Request {
...
}
 "/home/username/.stack/build-plan/lts-xx.yy.yaml" (Response {responseStatus = Status {statusCode = 404, statusMessage = "Not Found"},
```

You are probably running an old stack version and need
to upgrade it. Try running:

```bash
stack upgrade
```

Or see other options for upgrading at [Stack documentation](https://docs.haskellstack.org/en/stable/install_and_upgrade/#upgrade).

#### Otherwise, if you get an error message like this...

```
No compiler found, expected minor version match with...
Try running "stack setup" to install the correct GHC...
```

Just do as it says and it will download and install
the correct compiler version:

```bash
stack setup
```

If you want to play with your solution in GHCi, just run the command:

```bash
stack ghci
```

## Submitting your solution

You can submit your solution using the `exercism submit src/HelloWorld.hs package.yaml` command.
This command will upload your solution to the Exercism website and print the solution page's URL.

It's possible to submit an incomplete solution which allows you to:

- See how others have completed the exercise
- Request help from a mentor

## Need to get help?

If you'd like help solving the exercise, check the following pages:

- The [Haskell track's documentation](https://exercism.org/docs/tracks/haskell)
- [Exercism's programming category on the forum](https://forum.exercism.org/c/programming/5)
- The [Frequently Asked Questions](https://exercism.org/docs/using/faqs)

Should those resources not suffice, you could submit your (incomplete) solution to request mentoring.

## Getting Started

Please refer to the [installation](https://exercism.io/tracks/haskell/installation)
and [learning](https://exercism.io/tracks/haskell/learning) help pages.

## Feedback, Issues, Pull Requests

The [exercism/haskell](https://github.com/exercism/haskell) repository on
GitHub is the home for all of the Haskell exercises.

If you have feedback about an exercise, or want to help implementing a new
one, head over there and create an issue.  We'll do our best to help you!
