//%attributes = {}
//For ($i; 1; 100)
//CREATE RECORD([Table_1])
//SAVE RECORD([Table_1])
//End for 
CREATE EMPTY SET:C140([Table_1:1]; "random")
CREATE EMPTY SET:C140([Table_1:1]; "all")
CREATE EMPTY SET:C140([Table_1:1]; "mixed")
ALL RECORDS:C47([Table_1:1])

$map:=[]
For ($i; 1; Random:C100%Records in table:C83([Table_1:1]))
	$idx:=Random:C100%Records in selection:C76([Table_1:1])
	GOTO SELECTED RECORD:C245([Table_1:1]; $idx)
	ADD TO SET:C119([Table_1:1]; "random")
	$map[$idx]:=1
	NEXT RECORD:C51([Table_1:1])
End for 
TEXT TO DOCUMENT:C1237(System folder:C487(Desktop:K41:16)+"random.json"; JSON Stringify:C1217($map))
SAVE SET:C184("random"; System folder:C487(Desktop:K41:16)+"random.4st")
CLEAR SET:C117("random")

$map:=[]
FIRST RECORD:C50([Table_1:1])
For ($i; 1; Records in table:C83([Table_1:1]))
	ADD TO SET:C119([Table_1:1]; "all")
	$map[$i]:=1
	NEXT RECORD:C51([Table_1:1])
End for 
TEXT TO DOCUMENT:C1237(System folder:C487(Desktop:K41:16)+"all.json"; JSON Stringify:C1217($map))
SAVE SET:C184("all"; System folder:C487(Desktop:K41:16)+"all.4st")
CLEAR SET:C117("all")

$map:=[]
FIRST RECORD:C50([Table_1:1])
For ($i; 1; Records in table:C83([Table_1:1])\2)
	If ((Random:C100%2)=0)
		ADD TO SET:C119([Table_1:1]; "mixed")
		$map[$i]:=1
	End if 
	NEXT RECORD:C51([Table_1:1])
End for 

While (Not:C34(End selection:C36([Table_1:1])))
	ADD TO SET:C119([Table_1:1]; "mixed")
	$i+=1
	$map[$i]:=1
	NEXT RECORD:C51([Table_1:1])
End while 

TEXT TO DOCUMENT:C1237(System folder:C487(Desktop:K41:16)+"mixed.json"; JSON Stringify:C1217($map))
SAVE SET:C184("mixed"; System folder:C487(Desktop:K41:16)+"mixed.4st")
CLEAR SET:C117("mixed")