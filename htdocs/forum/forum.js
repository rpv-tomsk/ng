function forum_prepare_editor(editor_code, param) {
    if (editor_code == "extend") {
        $(document).ready(function() {
            $("textarea[jseditor]").each(function() {
                new editor(this, param);
            });
        });
    };
}