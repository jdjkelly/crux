// CruxCFI - EPUB CFI fragment identifier utilities
const CruxCFI = {
    getPathToNode: function(node) {
        const path = [];
        let current = node;
        while (current && current !== document.body && current.parentNode) {
            const parent = current.parentNode;
            const children = Array.from(parent.childNodes).filter(c =>
                c.nodeType !== Node.TEXT_NODE || c.textContent.trim() !== ''
            );
            let position = 0;
            for (let i = 0; i < children.length; i++) {
                position++;
                if (children[i] === current) break;
            }
            path.unshift(position);
            current = parent;
        }
        return '/' + path.join('/');
    },

    getSelectionCFI: function() {
        const selection = window.getSelection();
        if (!selection || selection.isCollapsed || selection.rangeCount === 0) return null;

        const range = selection.getRangeAt(0);
        const text = selection.toString().trim();
        if (!text) return null;

        let startNode = range.startContainer;
        let endNode = range.endContainer;

        if (startNode.nodeType !== Node.TEXT_NODE) {
            startNode = this.getFirstTextNode(startNode);
        }
        if (endNode.nodeType !== Node.TEXT_NODE) {
            endNode = this.getLastTextNode(endNode);
        }
        if (!startNode || !endNode) return null;

        const context = this.getSurroundingContext(range, 500);

        return {
            startPath: this.getPathToNode(startNode),
            startOffset: range.startOffset,
            endPath: this.getPathToNode(endNode),
            endOffset: range.endOffset,
            text: text,
            context: context
        };
    },

    getFirstTextNode: function(node) {
        if (node.nodeType === Node.TEXT_NODE) return node;
        for (const child of node.childNodes) {
            const result = this.getFirstTextNode(child);
            if (result) return result;
        }
        return null;
    },

    getLastTextNode: function(node) {
        if (node.nodeType === Node.TEXT_NODE) return node;
        for (let i = node.childNodes.length - 1; i >= 0; i--) {
            const result = this.getLastTextNode(node.childNodes[i]);
            if (result) return result;
        }
        return null;
    },

    getSurroundingContext: function(range, contextLength) {
        const body = document.body;
        const fullText = body.textContent || '';
        const preRange = document.createRange();
        preRange.setStart(body, 0);
        preRange.setEnd(range.startContainer, range.startOffset);
        const startPos = preRange.toString().length;
        const endPos = startPos + range.toString().length;
        const contextStart = Math.max(0, startPos - contextLength);
        const contextEnd = Math.min(fullText.length, endPos + contextLength);
        return fullText.substring(contextStart, contextEnd);
    }
};
