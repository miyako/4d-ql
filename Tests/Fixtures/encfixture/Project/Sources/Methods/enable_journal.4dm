//%attributes = {"invisible":true}
// Configures a journal file for the open data file. 4D records the path in the
// data file's extra properties ("journal_file.next_filepath") and starts writing
// the journal after the next backup.
var $journal : Text
$journal:=Get 4D folder(Database folder)+"Data"+Folder separator+"fixture.journal"
SELECT LOG FILE($journal)
LOG EVENT(Into system standard outputs; "OK="+String(OK)+"\n")
QUIT 4D
