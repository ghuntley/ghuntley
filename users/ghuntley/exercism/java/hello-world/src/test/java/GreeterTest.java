/*
 * Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
 * SPDX-License-Identifier: Proprietary
 */

import org.junit.Test;

import static org.assertj.core.api.Assertions.assertThat;

public class GreeterTest {

    @Test
    public void testThatGreeterReturnsTheCorrectGreeting() {
        assertThat(new Greeter().getGreeting()).isEqualTo("Hello, World!");
    }

}
