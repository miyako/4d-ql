ON ERR CALL("")
var $e : Object
For each ($e; Last errors)
	vp_log("ERROR "+String($e.errCode)+" "+$e.message+" ("+Error method+":"+String(Error line)+")")
End for each
var $out : 4D.Folder
$out:=Folder("/PACKAGE/Output")
$out.file("error.txt").setText("Native command failed; see run.log")
QUIT 4D
