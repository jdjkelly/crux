// CruxSearch - In-chapter text search with live highlighting
const CruxSearch = {
    searchHighlights: [],
    currentIndex: -1,
    query: '',

    // Perform search and apply highlights
    search: function(query) {
        this.clearHighlights();
        this.query = query;

        if (!query || query.length === 0) {
            this.reportResults();
            return;
        }

        const content = document.querySelector('.crux-content');
        if (!content) return;

        // Collect all matches first
        const matches = [];
        const walker = document.createTreeWalker(
            content,
            NodeFilter.SHOW_TEXT,
            null,
            false
        );

        const regex = new RegExp(this.escapeRegex(query), 'gi');
        let node;

        while (node = walker.nextNode()) {
            // Skip nodes inside existing highlights or margin notes
            if (node.parentElement.closest('.crux-search-highlight, .crux-highlight, .crux-margin')) {
                continue;
            }

            const text = node.textContent;
            let match;
            regex.lastIndex = 0;

            while ((match = regex.exec(text)) !== null) {
                matches.push({
                    node: node,
                    start: match.index,
                    end: match.index + match[0].length,
                    text: match[0]
                });
            }
        }

        // Apply highlights in reverse order to preserve offsets
        matches.reverse().forEach((m, i) => {
            this.highlightMatch(m, matches.length - 1 - i);
        });

        this.searchHighlights = Array.from(
            document.querySelectorAll('.crux-search-highlight')
        );

        // Jump to first match
        if (this.searchHighlights.length > 0) {
            this.currentIndex = 0;
            this.updateCurrentHighlight();
        }

        this.reportResults();
    },

    highlightMatch: function(match, index) {
        const node = match.node;
        const text = node.textContent;

        const before = text.substring(0, match.start);
        const matched = text.substring(match.start, match.end);
        const after = text.substring(match.end);

        const frag = document.createDocumentFragment();
        if (before) frag.appendChild(document.createTextNode(before));

        const span = document.createElement('span');
        span.className = 'crux-search-highlight';
        span.dataset.searchIndex = index;
        span.textContent = matched;
        frag.appendChild(span);

        if (after) frag.appendChild(document.createTextNode(after));

        node.parentNode.replaceChild(frag, node);
    },

    clearHighlights: function() {
        const highlights = document.querySelectorAll('.crux-search-highlight');
        highlights.forEach(span => {
            const parent = span.parentNode;
            if (parent) {
                while (span.firstChild) {
                    parent.insertBefore(span.firstChild, span);
                }
                parent.removeChild(span);
                parent.normalize();
            }
        });
        this.searchHighlights = [];
        this.currentIndex = -1;
    },

    nextMatch: function() {
        if (this.searchHighlights.length === 0) return;
        this.currentIndex = (this.currentIndex + 1) % this.searchHighlights.length;
        this.updateCurrentHighlight();
        this.reportResults();
    },

    previousMatch: function() {
        if (this.searchHighlights.length === 0) return;
        this.currentIndex = (this.currentIndex - 1 + this.searchHighlights.length) % this.searchHighlights.length;
        this.updateCurrentHighlight();
        this.reportResults();
    },

    updateCurrentHighlight: function() {
        // Remove current class from all
        this.searchHighlights.forEach(el => el.classList.remove('crux-search-current'));

        // Add to current
        if (this.currentIndex >= 0 && this.currentIndex < this.searchHighlights.length) {
            const current = this.searchHighlights[this.currentIndex];
            current.classList.add('crux-search-current');
            current.scrollIntoView({ behavior: 'smooth', block: 'center' });
        }
    },

    reportResults: function() {
        if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.searchResults) {
            window.webkit.messageHandlers.searchResults.postMessage({
                matchCount: this.searchHighlights.length,
                currentIndex: this.currentIndex
            });
        }
    },

    escapeRegex: function(string) {
        return string.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
};
