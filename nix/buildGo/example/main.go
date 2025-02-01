// Copyright 2019 Google LLC.
// SPDX-License-Identifier: Apache-2.0
//
// Package main provides a tiny example program for the Bazel-style
// Nix build system for Go.

package main

import (
	"example"
	"exampleproto"
	"fmt"
)

var Flag string = "unsuccessfully"

func main() {
	thing := exampleproto.Thing{
		Id:          example.UUID(),
		KindOfThing: "test thing",
	}

	fmt.Printf("The thing is a %s with ID %q\n", thing.Id, thing.KindOfThing)
	fmt.Printf("The flag has been %s set\n", Flag)
}
