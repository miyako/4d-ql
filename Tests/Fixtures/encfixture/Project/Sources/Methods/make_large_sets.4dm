//%attributes = {"invisible":true}
var $out; $name : Text
var $names : Collection
Get database parameter(User param value; $out)
$out:=Convert path POSIX to system($out)
ARRAY BOOLEAN($bits; 33587200)
CREATE SET FROM ARRAY([Plain]; $bits; "large")
SAVE SET("large"; $out+"large-address-empty.4st")
LOG EVENT(Into system standard outputs; "large empty count="+String(Records in set("large"))+"\n")
CLEAR SET("large")
ARRAY BOOLEAN($bits; 0)
$names:=["billion-sparse"; "large-bitmap"]
For each ($name; $names)
	LOAD SET([Plain]; "large"; $out+$name+"-input.4st")
	LOG EVENT(Into system standard outputs; $name+" loaded OK="+String(OK)+" count="+String(Records in set("large"))+"\n")
	SAVE SET("large"; $out+$name+".4st")
	LOG EVENT(Into system standard outputs; $name+" saved OK="+String(OK)+"\n")
	CLEAR SET("large")
End for each
