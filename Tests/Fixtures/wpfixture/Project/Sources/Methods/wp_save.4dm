#DECLARE($doc : Object; $name : Text)
var $folder : Text:=Get 4D folder(Database folder)+"Output"+Folder separator
CREATE FOLDER($folder; *)
WP EXPORT DOCUMENT($doc; $folder+$name+".4wp"; wk 4wp)
WP EXPORT DOCUMENT($doc; $folder+$name+".pdf"; wk pdf)
wp_log("SAVED "+$name)
