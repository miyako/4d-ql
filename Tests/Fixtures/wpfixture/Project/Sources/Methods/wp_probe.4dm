ON ERR CALL("wp_err")
ARRAY TEXT($allowed; 1)
$allowed{1}:="wp_*"
SET ALLOWED METHODS($allowed)
wp_check
var $name : Text
For each ($name; ["wp_text"; "wp_layout"; "wp_objects"; "wp_table"; "wp_media"; "wp_more"])
	wp_log("BEGIN "+$name)
	EXECUTE METHOD($name)
End for each
ON ERR CALL("")
QUIT 4D
