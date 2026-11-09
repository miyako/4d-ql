//%attributes = {"invisible":true}
var $i : Integer
var $e : 4D.Entity
var $out : Text
Get database parameter(User param value; $out)
$out:=Convert path POSIX to system($out)
START TRANSACTION
For ($i; ds.Plain.all().length+1; 1000000)
	$e:=ds.Plain.new()
	$e.name:=String($i)
	$e.save()
	If (($i%10000)=0)
		VALIDATE TRANSACTION
		START TRANSACTION
	End if
End for
VALIDATE TRANSACTION
ALL RECORDS([Plain])
CREATE SET([Plain]; "million")
SAVE SET("million"; $out+"million-full.4st")
LOG EVENT(Into system standard outputs; "million-full count="+String(Records in set("million"))+"\n")
ARRAY BOOLEAN($bits; 1000000)
For ($i; 0; 999999; 2)
	$bits{$i}:=True
End for
CREATE SET FROM ARRAY([Plain]; $bits; "million")
SAVE SET("million"; $out+"million-alternating.4st")
LOG EVENT(Into system standard outputs; "million-alternating count="+String(Records in set("million"))+"\n")
QUIT 4D
