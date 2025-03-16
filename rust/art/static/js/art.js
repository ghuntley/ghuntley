/**
 * Art - Git Repository Browser
 * Main JavaScript functionality
 */

document.addEventListener('DOMContentLoaded', () => {
    // Add the current year to the footer
    const yearElement = document.querySelector('.site-footer span.year');
    if (yearElement) {
        yearElement.textContent = new Date().getFullYear();
    }

    // Add copy button to commit hashes
    const hashElements = document.querySelectorAll('.full-hash');
    hashElements.forEach(el => {
        const button = document.createElement('button');
        button.className = 'copy-button';
        button.title = 'Copy to clipboard';
        button.innerHTML = 'Copy';
        button.style.marginLeft = '8px';
        button.style.fontSize = '12px';
        button.style.padding = '2px 6px';

        button.addEventListener('click', async () => {
            try {
                await navigator.clipboard.writeText(el.textContent.trim());
                const originalText = button.innerHTML;
                button.innerHTML = 'Copied!';
                setTimeout(() => {
                    button.innerHTML = originalText;
                }, 2000);
            } catch (err) {
                console.error('Failed to copy text: ', err);
            }
        });

        el.appendChild(button);
    });

    // File navigation keyboard shortcuts
    if (document.querySelector('.file-table')) {
        document.addEventListener('keydown', (e) => {
            // Navigate up and down the file list with j and k keys
            if (document.activeElement === document.body) {
                const fileRows = document.querySelectorAll('.file-entry');
                let currentIndex = -1;

                // Find the currently highlighted row
                fileRows.forEach((row, index) => {
                    if (row.classList.contains('highlight')) {
                        currentIndex = index;
                    }
                });

                if (e.key === 'j') {
                    // Navigate down
                    if (currentIndex === -1) {
                        fileRows[0]?.classList.add('highlight');
                    } else if (currentIndex < fileRows.length - 1) {
                        fileRows[currentIndex].classList.remove('highlight');
                        fileRows[currentIndex + 1].classList.add('highlight');
                    }
                } else if (e.key === 'k') {
                    // Navigate up
                    if (currentIndex > 0) {
                        fileRows[currentIndex].classList.remove('highlight');
                        fileRows[currentIndex - 1].classList.add('highlight');
                    }
                } else if (e.key === 'Enter') {
                    // Follow link for highlighted row
                    if (currentIndex !== -1) {
                        const link = fileRows[currentIndex].querySelector('a');
                        if (link) {
                            link.click();
                        }
                    }
                }
            }
        });
    }

    // Add filter input for branches and tags
    const setupFilter = (listSelector, inputSelector) => {
        const listElement = document.querySelector(listSelector);
        const inputElement = document.querySelector(inputSelector);

        if (listElement && inputElement) {
            inputElement.addEventListener('input', () => {
                const filter = inputElement.value.toLowerCase();
                const items = listElement.querySelectorAll('li');

                items.forEach(item => {
                    const text = item.textContent.toLowerCase();
                    item.style.display = text.includes(filter) ? '' : 'none';
                });
            });
        }
    };

    setupFilter('.branch-list', '.branch-filter');
    setupFilter('.tag-list', '.tag-filter');

    // Syntax highlighting line highlighting
    const highlightLine = () => {
        if (window.location.hash && window.location.hash.startsWith('#L')) {
            const lineNumber = parseInt(window.location.hash.substring(2));
            if (!isNaN(lineNumber)) {
                const lineElement = document.querySelector(`.line-number[data-line="${lineNumber}"]`);
                if (lineElement) {
                    lineElement.closest('tr')?.classList.add('highlight-line');
                    lineElement.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
            }
        }
    };

    highlightLine();
    window.addEventListener('hashchange', highlightLine);

    // Toggle dark mode
    const toggleDarkMode = document.getElementById('toggle-dark-mode');
    if (toggleDarkMode) {
        toggleDarkMode.addEventListener('click', () => {
            document.documentElement.classList.toggle('dark-mode');
            localStorage.setItem('dark-mode', document.documentElement.classList.contains('dark-mode'));
        });

        // Check stored preference
        if (localStorage.getItem('dark-mode') === 'true') {
            document.documentElement.classList.add('dark-mode');
        }
    }
});
