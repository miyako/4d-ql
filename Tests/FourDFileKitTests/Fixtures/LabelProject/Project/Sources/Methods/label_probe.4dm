var $mode; $dom; $size : Text
var $file : 4D.File
var $context : Object
var $picture : Picture
Get database parameter(User param value; $mode)
SET APPLICATION COLOR SCHEME("light")
$file:=File("/RESOURCES/native/context.json")
$file.parent.create()
$context:={mode: $mode; stage: "entered"; version: Application version; records: 0}
$file.setText(JSON Stringify($context; *))
CREATE RECORD([Parcels])
[Parcels]ID:=1
[Parcels]Recipient:="Ada Example"
SAVE RECORD([Parcels])
ALL RECORDS([Parcels])
$context.records:=Records in selection([Parcels])
$context.stage:="records-created"
$file.setText(JSON Stringify($context; *))
$dom:=DOM Parse XML source(File("/RESOURCES/Labels/representative.4lbp").platformPath)
$context.xmlParsed:=(OK=1)
DOM EXPORT TO FILE($dom; File("/RESOURCES/native/representative-roundtrip.4lbp").platformPath)
$context.xmlExported:=(OK=1)
DOM CLOSE XML($dom)
$file.setText(JSON Stringify($context; *))
If ($mode="editor")
  $context.stage:="entering-wizard"
  $file.setText(JSON Stringify($context; *))
  PRINT LABEL([Parcels]; Char(1))
Else
  SET PRINT PREVIEW(False)
  SET PRINT OPTION(Destination option; 3; File("/RESOURCES/native/representative.pdf").platformPath)
  $context.destinationConfigured:=(OK=1)
  $context.stage:="entering-print-label"
  $file.setText(JSON Stringify($context; *))
  PRINT LABEL([Parcels]; File("/RESOURCES/Labels/representative.4lbp").platformPath; >)
  $context.printOK:=OK
  $dom:=DOM Parse XML source(File("/RESOURCES/Labels/representative.4lbp").platformPath)
  $size:=DOM Find XML element by ID($dom; "size")
  DOM SET XML ATTRIBUTE($size; "unit"; "mm")
  DOM EXPORT TO FILE($dom; File("/RESOURCES/native/display-unit-mm.4lbp").platformPath)
  DOM CLOSE XML($dom)
  FIRST RECORD([Parcels])
  SET PRINT OPTION(Destination option; 3; File("/RESOURCES/native/display-unit-mm.pdf").platformPath)
  PRINT LABEL([Parcels]; File("/RESOURCES/native/display-unit-mm.4lbp").platformPath; >)
  $context.unitMMPrintOK:=OK
  FORM SCREENSHOT([Parcels]; "ShippingLabel"; $picture)
  WRITE PICTURE FILE(File("/RESOURCES/native/host-form.png").platformPath; $picture)
  FIRST RECORD([Parcels])
  SET PRINT OPTION(Destination option; 3; File("/RESOURCES/native/saved-form.pdf").platformPath)
  PRINT LABEL([Parcels]; File("/RESOURCES/Labels/saved-form-reference.4lbp").platformPath; >)
  $context.savedFormPrintOK:=OK
End if
$context.stage:="complete"
$file.setText(JSON Stringify($context; *))
LOG EVENT(Into system standard outputs; JSON Stringify($context; *); Information message)
QUIT 4D
