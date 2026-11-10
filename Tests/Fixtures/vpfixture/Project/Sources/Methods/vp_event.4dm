var $event : Object
$event:=FORM Event
Case of
	: ($event.code=On VP Ready)
		vp_log("On VP Ready")
		VP SET TEXT VALUE(VP Cell(This.area; 0; 0); "Hello View Pro")
		VP SET NUM VALUE(VP Cell(This.area; 1; 0); 1234.5)
		VP SET BOOLEAN VALUE(VP Cell(This.area; 2; 0); True)
		VP SET DATE VALUE(VP Cell(This.area; 3; 0); !2024-02-29!)
		VP SET FORMULA(VP Cell(This.area; 4; 0); "=B1*2")
		VP SET TEXT VALUE(VP Cell(This.area; 0; 1); "日本語 / café / 😀")
		VP SET TEXT VALUE(VP Cell(This.area; 1; 1); "")
		VP SET BOOLEAN VALUE(VP Cell(This.area; 2; 1); False)
		VP SET NUM VALUE(VP Cell(This.area; 3; 1); -0.125)
		VP SET FORMULA(VP Cell(This.area; 4; 1); "=1/0")
		VP SET FORMULA(VP Cell(This.area; 4; 2); "=\"Result: \"&A1")
		VP SET DATE VALUE(VP Cell(This.area; 3; 2); !1899-12-30!)
		VP SET CELL STYLE(VP Cell(This.area; 3; 1); {formatter: "0.0%"})
		VP SET CELL STYLE(VP Cell(This.area; 3; 2); {formatter: "yyyy-mm-dd"})
		VP SET CELL STYLE(VP Cell(This.area; 1; 0); {formatter: "#,##0.00"; backColor: "#e8f0fe"; foreColor: "#123456"; font: "bold 14pt Arial"})
		This.formula:=Formula(vp_exported)
		VP EXPORT DOCUMENT(This.area; This.output.file("typed.4vp").platformPath; This)
	: ($event.code=On URL Loading Error)
		vp_log("ERROR Web Area loading failed")
		This.result:={success: False; error: "Web Area loading failed"}
		CANCEL
End case
