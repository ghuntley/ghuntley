// Copyright (c) 2020 Geoffrey Huntley <ghuntley@ghuntley.com>. All rights reserved.
// SPDX-License-Identifier: Proprietary

// press "e" to fork and edit the current page
$(document).ready(function() {
    $('body').keypress(function(event) {
        if (event.which == 101) {
            event.preventDefault();
            window.location = $('.github-corner')[0].href;
        }
    });
});

