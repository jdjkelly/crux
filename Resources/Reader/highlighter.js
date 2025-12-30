// CruxHighlighter - DOM highlight application and management
const CruxHighlighter = {
    highlights: new Map(),

    findNodeByPath: function(path) {
        const parts = path.split('/').filter(p => p !== '');
        let current = document.body;
        for (const part of parts) {
            const index = parseInt(part, 10);
            if (isNaN(index)) return null;
            const children = Array.from(current.childNodes).filter(c =>
                c.nodeType !== Node.TEXT_NODE || c.textContent.trim() !== ''
            );
            if (index < 1 || index > children.length) return null;
            current = children[index - 1];
        }
        return current;
    },

    applyHighlight: function(data) {
        const { id, startPath, startOffset, endPath, endOffset } = data;
        const startNode = this.findNodeByPath(startPath);
        const endNode = this.findNodeByPath(endPath);

        if (!startNode || !endNode) return false;
        if (startNode.nodeType !== Node.TEXT_NODE || endNode.nodeType !== Node.TEXT_NODE) return false;
        if (startOffset > startNode.textContent.length || endOffset > endNode.textContent.length) return false;

        try {
            const range = document.createRange();
            range.setStart(startNode, startOffset);
            range.setEnd(endNode, endOffset);

            if (range.startContainer === range.endContainer) {
                const span = document.createElement('span');
                span.className = 'crux-highlight';
                span.dataset.highlightId = id;
                range.surroundContents(span);
                span.addEventListener('click', () => {
                    CruxHighlighter.scrollHighlightToActiveZone(id);
                });
                this.highlights.set(id, [span]);
            } else {
                // Cross-element: wrap each text node portion
                const walker = document.createTreeWalker(
                    range.commonAncestorContainer,
                    NodeFilter.SHOW_TEXT,
                    null,
                    false
                );
                const textNodes = [];
                let started = false;
                let node;
                while (node = walker.nextNode()) {
                    if (node === range.startContainer) started = true;
                    if (started) textNodes.push(node);
                    if (node === range.endContainer) break;
                }

                const elements = [];
                for (let i = 0; i < textNodes.length; i++) {
                    const textNode = textNodes[i];
                    let start = (i === 0) ? range.startOffset : 0;
                    let end = (i === textNodes.length - 1) ? range.endOffset : textNode.textContent.length;

                    if (start === 0 && end === textNode.textContent.length) {
                        const span = document.createElement('span');
                        span.className = 'crux-highlight';
                        span.dataset.highlightId = id;
                        span.textContent = textNode.textContent;
                        textNode.parentNode.replaceChild(span, textNode);
                        span.addEventListener('click', () => {
                            window.webkit.messageHandlers.highlightTapped.postMessage(id);
                        });
                        elements.push(span);
                    } else {
                        const before = textNode.textContent.substring(0, start);
                        const middle = textNode.textContent.substring(start, end);
                        const after = textNode.textContent.substring(end);

                        const frag = document.createDocumentFragment();
                        if (before) frag.appendChild(document.createTextNode(before));
                        const span = document.createElement('span');
                        span.className = 'crux-highlight';
                        span.dataset.highlightId = id;
                        span.textContent = middle;
                        span.addEventListener('click', () => {
                            window.webkit.messageHandlers.highlightTapped.postMessage(id);
                        });
                        frag.appendChild(span);
                        if (after) frag.appendChild(document.createTextNode(after));
                        textNode.parentNode.replaceChild(frag, textNode);
                        elements.push(span);
                    }
                }
                this.highlights.set(id, elements);
            }
            return true;
        } catch (e) {
            console.error('Error applying highlight:', e);
            return false;
        }
    },

    applyHighlights: function(highlightsArray) {
        // Remove highlights that are no longer in the array (e.g., old pending selection)
        const newIds = new Set(highlightsArray.map(h => h.id));
        for (const [id, elements] of this.highlights) {
            if (!newIds.has(id)) {
                this.removeHighlight(id);
            }
        }

        // Apply new highlights
        for (const h of highlightsArray) {
            if (!this.highlights.has(h.id)) {
                this.applyHighlight(h);
            }
        }
    },

    clearAllHighlights: function() {
        for (const [id, elements] of this.highlights) {
            for (const span of elements) {
                const parent = span.parentNode;
                if (parent) {
                    while (span.firstChild) parent.insertBefore(span.firstChild, span);
                    parent.removeChild(span);
                    parent.normalize();
                }
            }
        }
        this.highlights.clear();
    },

    removeHighlight: function(highlightId) {
        const elements = this.highlights.get(highlightId);
        if (!elements) return;
        for (const span of elements) {
            const parent = span.parentNode;
            if (parent) {
                while (span.firstChild) parent.insertBefore(span.firstChild, span);
                parent.removeChild(span);
                parent.normalize();
            }
        }
        this.highlights.delete(highlightId);
    },

    getAllHighlightPositions: function() {
        const results = [];

        for (const [id, elements] of this.highlights) {
            if (elements.length === 0) continue;

            // Get first element's position (where note should anchor)
            const firstEl = elements[0];
            const rect = firstEl.getBoundingClientRect();

            results.push({
                id: id,
                viewportY: rect.top,
                height: rect.height
            });
        }

        // Sort by vertical position (top to bottom)
        results.sort((a, b) => a.viewportY - b.viewportY);

        return results;
    },

    reportHighlightPositions: function() {
        const positions = this.getAllHighlightPositions();
        window.webkit.messageHandlers.highlightPositions.postMessage(positions);
    },

    scrollHighlightToActiveZone: function(highlightId, offset = 80) {
        const elements = this.highlights.get(highlightId);
        if (!elements || elements.length === 0) return;

        const firstEl = elements[0];
        const rect = firstEl.getBoundingClientRect();
        const scrollTarget = window.scrollY + rect.top - offset;

        window.scrollTo({
            top: Math.max(0, scrollTarget),
            behavior: 'smooth'
        });
    },

    scrollToAnchor: function(anchorId) {
        const element = document.getElementById(anchorId);
        if (element) {
            element.scrollIntoView({ behavior: 'instant', block: 'start' });
            return true;
        }
        return false;
    }
};
