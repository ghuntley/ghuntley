// Copyright (c) 2022 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

using Xunit;

public class HelloWorldTests
{
    [Fact]
    public void Say_hi_()
    {
        Assert.Equal("Hello, World!", HelloWorld.Hello());
    }
}
