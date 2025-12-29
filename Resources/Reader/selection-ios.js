// iOS: Use selectionchange for touch-based selection
document.addEventListener('selectionchange', function() {
    // Ignore selections within margin notes
    const selection = window.getSelection();
    if (selection && selection.anchorNode) {
        const anchor = selection.anchorNode.nodeType === Node.TEXT_NODE
            ? selection.anchorNode.parentElement
            : selection.anchorNode;
        if (anchor && (anchor.closest('.crux-margin-note') || anchor.closest('.crux-margin'))) {
            return;
        }
    }
    const cfiData = CruxCFI.getSelectionCFI();
    if (cfiData && cfiData.text.length > 0) {
        window.webkit.messageHandlers.textSelection.postMessage(cfiData);
    }
});
