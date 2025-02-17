/*
 * SPDX-License-Identifier: GPL-3.0-or-later
 * SPDX-FileCopyrightText: 2021 Matthias Joachim Geisler, openwebcraft <matthiasjg@openwebcraft.com>
 */

class Journal.Controller : Object {
    static Controller __instance;

    private Journal.LogModel[] ? _logs;

    private Journal.LogDao _log_dao;

    private Journal.LogReader _log_reader;
    private Journal.LogWriter _log_writer;

    public signal void updated_journal_logs (string log_filter, bool is_tag_filter, LogModel[] logs);

    public static Controller shared_instance () {
        if (__instance == null) {
            __instance = new Journal.Controller ();
        }
        return __instance;
    }

    public void add_journal_log_entry (string log_txt = "") {
        if (log_txt == "") {
            return;
        }

        if (_log_dao == null) {
            _log_dao = new Journal.LogDao ();
        }
        var log = new Journal.LogModel (log_txt);
        var log_inserted = _log_dao.insert_entity (log);
        debug ("log_inserted: %s", log_inserted.to_string ());
        load_journal_logs ();
    }

    public void load_journal_logs (string log_filter = "") {
        if (_log_dao == null) {
            _log_dao = new Journal.LogDao ();
        }

        if (log_filter == "") {
            _logs = _log_dao.select_all_entities ();
        } else {
            _logs = _log_dao.select_entities_where_column_like (
                Journal.LogDao.SQL_COLUMN_NAME_LOG,
                log_filter);
        }
        debug ("Loaded %d Journal logs filtered for %s", _logs.length, log_filter);

        Regex? tag_regex = null;
        try {
            tag_regex = new Regex ("^#\\w+$");
        } catch (Error err) {
            critical (err.message);
        }
        var is_tag_filter = tag_regex.match (log_filter);

        updated_journal_logs (log_filter, is_tag_filter, _logs);
    }

    private File ? choose_json_file (
        Gtk.FileChooserAction action,
        string label = "Choose JSON File",
        string json_file_name = ""
    ) {
        var json_filter = new Gtk.FileFilter ();
        json_filter.add_pattern ("*.json");
        json_filter.set_filter_name (_("JSON (*.json)"));

        var action_label = action == Gtk.FileChooserAction.SAVE ? _("Save") : _("Open");

        var file_chooser = new Gtk.FileChooserNative (
            label,
            null,
            action,
            action_label,
            _("Cancel")
        );
        if (json_file_name != "") {
            file_chooser.do_overwrite_confirmation = true;
            file_chooser.set_current_name (json_file_name);
        }
        file_chooser.add_filter (json_filter);
        file_chooser.set_current_folder (Environment.get_home_dir ());

        string file = "";
        string name = "";
        string extension = "";
        if (file_chooser.run () == Gtk.ResponseType.ACCEPT) {
            file = file_chooser.get_filename ();
            extension = file.slice (file.last_index_of (".", 0), file.length);

            if (extension.length == 0 || extension[0] != '.') {
                extension = ".json";
                file += extension;
            }

            name = file.slice (file.last_index_of ("/", 0) + 1, file.last_index_of (".", 0));
            message ("name is %s extension is %s\n", name, extension);
        }

        file_chooser.destroy ();

        if (file != "") {
            var f = File.new_for_path (file);
            return f;
        }

        return null;
    }

    public void import_journal () {
        File ? file = choose_json_file (Gtk.FileChooserAction.OPEN, _("Reset and Restore Journal"));
        if (file != null) {
            if (_log_reader == null) {
                _log_reader = Journal.LogReader.shared_instance ();
            }
            var logs = _log_reader.load_journal_from_json_file (file.get_path ());

            // force re-create db, i.e. reset
            _log_dao = new Journal.LogDao (Journal.BaseDao.DB_FILE_NAME, true);

            for (uint i = 0; i < logs.length; i++) {
                var log = (Journal.LogModel) logs[i];
                Journal.LogModel log_inserted = _log_dao.insert_entity (log);
                debug ("log_inserted: %s", log_inserted.to_string ());
            }
            debug ("Imported Journal with %d logs", logs.length);
            updated_journal_logs ("", false, logs);
        }
    }

    public void export_journal () {
        var json_file_name = "TrimirJournal_backup_%s.json".printf (
            new DateTime.now_local ().format ("%Y-%m-%d")
        );

        File ? file = choose_json_file (Gtk.FileChooserAction.SAVE, _("Backup Journal"), json_file_name);
        if (file != null) {
            if (_log_dao == null) {
                _log_dao = new Journal.LogDao ();
            }
            Journal.LogModel[] ? logs = _log_dao.select_all_entities ();

            if (_log_writer == null) {
                _log_writer = Journal.LogWriter.shared_instance ();
            }
            _log_writer.write_journal_to_json_file (logs, file.get_path ());
        }
    }
}
