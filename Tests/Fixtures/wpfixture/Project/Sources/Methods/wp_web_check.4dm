var wpWebErrors : Collection:=New collection()
ON ERR CALL("wp_web_error")
ARRAY TEXT($allowed; 1)
$allowed{1}:="wp_*"
SET ALLOWED METHODS($allowed)
var $root : 4D.Folder:=Folder(Get 4D folder(Database folder); fk platform path)
var $manifest : Object:=JSON Parse($root.file("Input/cases.json").getText())
var $report : Object:=New object("version"; Application version(*); "cases"; New collection(); "errors"; wpWebErrors)
var $compilation : Object:=Compile project()
If (Not($compilation.success))
	wpWebErrors.push(New object("message"; "Probe compilation failed"; "details"; $compilation.errors))
Else
	var $case; $result; $doc; $reopened : Object
	For each ($case; $manifest.cases)
		$result:=New object("name"; $case.name)
		If (OB Is defined($case; "section"))
			var $sectionBaseline : Object:=WP Import document($root.file("Input/"+$case.section.source).platformPath)
			wp_section_apply($sectionBaseline; $case.section)
			$result.sectionExpected:=wp_section_stats($sectionBaseline)
			$result.sectionWebExpected:=wp_web_stats($sectionBaseline; False)
			WP EXPORT DOCUMENT($sectionBaseline; $root.file("Output/"+$case.name+"-expected.4wp").platformPath; wk 4wp)
		End if
		If (OB Is defined($case; "page"))
			var $baseline : Object:=WP Import document($root.file("Input/"+$case.page.source).platformPath)
			If ($case.page.target#"identity")
				wp_page_apply($baseline; $case.page.target)
			End if
			$result.pageExpected:=wp_web_stats($baseline; False)
			WP EXPORT DOCUMENT($baseline; $root.file("Output/"+$case.name+"-expected.pdf").platformPath; wk pdf)
			WP EXPORT DOCUMENT($baseline; $root.file("Output/"+$case.name+"-expected.4wp").platformPath; wk 4wp)
		End if
		$doc:=WP Import document($root.file("Input/"+$case.file).platformPath)
		If ($doc#Null)
			If (OB Is defined($case; "section"))
				$result.sectionImported:=wp_section_stats($doc)
			End if
			$result.imported:=wp_web_stats($doc; $case.name="new-document")
			If (OB Is defined($case; "page"))
				WP EXPORT DOCUMENT($doc; $root.file("Output/"+$case.name+".pdf").platformPath; wk pdf)
			End if
			WP EXPORT DOCUMENT($doc; $root.file("Output/"+$case.name+".4wp").platformPath; wk 4wp)
			$reopened:=WP Import document($root.file("Output/"+$case.name+".4wp").platformPath)
			If ($reopened#Null)
				If (OB Is defined($case; "section"))
					$result.sectionReopened:=wp_section_stats($reopened)
				End if
				$result.reopened:=wp_web_stats($reopened; $case.name="new-document")
			End if
		End if
		$report.cases.push($result)
		wp_log("NATIVE CASE "+$case.name)
	End for each
End if
$root.file("Output/native-report.json").setText(JSON Stringify($report; *))
ON ERR CALL("")
QUIT 4D
