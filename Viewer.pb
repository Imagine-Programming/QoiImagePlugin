; MIT License
; 
; Copyright (c) 2022 Bas Groothedde
; 
; Permission is hereby granted, free of charge, to any person obtaining a copy
; of this software and associated documentation files (the "Software"), to deal
; in the Software without restriction, including without limitation the rights
; to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
; copies of the Software, and to permit persons to whom the Software is
; furnished to do so, subject to the following conditions:
; 
; The above copyright notice and this permission notice shall be included in all
; copies or substantial portions of the Software.
; 
; THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
; IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
; FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
; AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
; LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
; OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
; SOFTWARE.

XIncludeFile "QoiImagePlugin.pbi"

Macro UiError(title, message)
  MessageRequester(title, message, #PB_MessageRequester_Error)
  End 1
EndMacro

;- QOI encoder init
UseQOIImageDecoder()
UseQOIImageEncoder()

;- Other decoder init
UsePNGImageDecoder()
UseJPEG2000ImageDecoder()
UseJPEGImageDecoder()
UseGIFImageDecoder()
UseTIFFImageDecoder()
UseTGAImageDecoder()

#GRID_PATTERN_SQUARE_SIZE = 10 ; size of a single square in the background grid
#GRID_PATTERN_CACHE_SIZE  = 50 ; the number of squares to prerender for the background grid in both directions
#GRID_PATTERN_CACHE_DIM   = #GRID_PATTERN_CACHE_SIZE * #GRID_PATTERN_SQUARE_SIZE
#GRID_ZOOM_STEP           = 2

; the flags and title to use for the opened window
#WINDOW_FLAGS = #PB_Window_ScreenCentered | #PB_Window_SystemMenu | #PB_Window_MinimizeGadget | #PB_Window_MaximizeGadget | #PB_Window_SizeGadget 
#WINDOW_TITLE = "QOI Viewer Demo"

; shortcut settings based on OS
CompilerIf #PB_Compiler_OS = #PB_OS_MacOS
  #SHORTCUT_MODIFIER_STRING  = "Cmd"
  #SHORTCUT_MODIFIER_KEY     = #PB_Shortcut_Command
  #SHORTCUT_CLOSE_MOD_STRING = #SHORTCUT_MODIFIER_STRING
  #SHORTCUT_CLOSE_STRING     = "W"
  #SHORTCUT_CLOSE_MOD_KEY    = #SHORTCUT_MODIFIER_KEY
  #SHORTCUT_CLOSE_KEY        = #PB_Shortcut_W 
CompilerElse
  #SHORTCUT_MODIFIER_STRING  = "Ctrl"
  #SHORTCUT_MODIFIER_KEY     = #PB_Shortcut_Control
  #SHORTCUT_CLOSE_MOD_STRING = "Alt"
  #SHORTCUT_CLOSE_STRING     = "F4"
  #SHORTCUT_CLOSE_MOD_KEY    = #PB_Shortcut_Alt
  #SHORTCUT_CLOSE_KEY        = #PB_Shortcut_F4
CompilerEndIf 

; menu item event IDs
Enumeration 100
  #MENU_ACTION_FILE_OPEN            ; File -> Open or relevant shortcut
  #MENU_ACTION_FILE_SAVE_AS         ; File -> Save As or relevant shortcut
  #MENU_ACTION_FILE_CLOSE           ; File -> Close or relevant shortcut
  
  #MENU_ACTION_VIEW_DEBUG = 150     ; View -> Show Debug Info
  #MENU_ACTION_VIEW_RESET_OFFSET    ; View -> Reset Offset
  #MENU_ACTION_VIEW_RESET_ZOOM      ; View -> Reset Zoom
  #MENU_ACTION_VIEW_ZOOM_ADD        ; View -> Zoom +
  #MENU_ACTION_VIEW_ZOOM_SUB        ; View -> Zoom -
  
  #MENU_ACTION_CANCEL_MOVE = 200    ; Escape key whilst moving the viewport
EndEnumeration

; file open/save patterns
#FILE_DIALOG_QOI_PATTERN = "QOI Image (*.qoi)|*.qoi"
#FILE_DIALOG_IMG_PATTERN = "Image File (*.qoi,*.png,*.jpg,*.jp2,*.jpeg,*.jfif,*.tiff,*.tga,*.bmp,*.gif)|*.qoi;*.png;*.jpg;*.jp2;*.jpeg;*.jfif;*.tiff;*.tga;*.bmp;*.gif"
#FILE_DIALOG_ALL_PATTERN = "All Files (*.*)|*.*"

; the canvas mouse state
Structure CanvasMouseState
  LeftMouseDown.i             ; #True when the left mouse is down or when the action has not been cancelled with Escape
  XStart.i                    ; X-coordinate of where the movement started
  YStart.i                    ; Y-coordinate of where the movement started
  XCurrent.i                  ; X-coordinate of the current mouse position
  YCurrent.i                  ; Y-coordinate of the current mouse position
  XOffset.i                   ; X-offset that was set when the movement started
  YOffset.i                   ; Y-offset that was set when the movement started
EndStructure

Structure CanvasDebugInfo
  ShowDebugInfo.i             ; Whether or not to render the debug info
  ImageLoadTime.i             ; The time in milliseconds it took to load the image
  PreviousRenderTime.i        ; The time in milliseconds it took to render the previous frame
  
  ImageWidth.i                ; The image width in pixels
  ImageHeight.i               ; The image height in pixels
  ImageDepth.i                ; The source image depth
  ImageRenderedDepth.i        ; The source image decoded depth
  
  ZoomLevel.i                 ; The current zoomlevel
  CurrentImageWidth.i         ; The zoomed width
  CurrentImageHeight.i        ; The zoomed height
  
  XOffset.i                   ; The X-offset of the image in the viewport
  YOffset.i                   ; The Y-offset of the image in the viewport
EndStructure

; the canvas image state
Structure CanvasImageState
  hCurrentlyLoadedImage.i     ; The currently loaded image to display
  hZoomedImage.i              ; The zoomed image to display 
  ZoomLevel.i                 ; The level of zoom in percentage
  XOffset.i                   ; The X-offset of the image in the viewport
  YOffset.i                   ; The Y-offset of the image in the viewport
  
  Mouse.CanvasMouseState      ; The current mouse movement state of the viewport
  DInfo.CanvasDebugInfo       ; Debug Information
EndStructure

Global Quit = #False 
Global hWindow 
Global hCanvas, hMenu
Global hDebugFont = LoadFont(#PB_Any, "Arial", 10)
Define CanvasImageState.CanvasImageState

; a rendering callback/filter for rendering a checker pattern.
; the callback is invoked per pixel being touched by a rendering operation.
; x: x coordinate of the current pixel
; y: y coordinate of the current pixel 
; top: the color being drawn on top
; bottom: the color already in the output
Procedure GridPatternCallback(x, y, top, bottom)
  Protected x1 = ((x + 1) / #GRID_PATTERN_SQUARE_SIZE)
  Protected y1 = ((y + 1) / #GRID_PATTERN_SQUARE_SIZE)
  
  If ((x1 + y1) % 2)
    ProcedureReturn top
  Else 
    ProcedureReturn bottom 
  EndIf 
EndProcedure

; render the pattern image enough times to fit the output buffer.
; hPatternImage: the image handle to the pre-rendered pattern.
; Procedure DrawGridPattern(hPatternImage)
;   Protected w = VectorOutputWidth() + #GRID_PATTERN_CACHE_DIM
;   Protected h = VectorOutputHeight() + #GRID_PATTERN_CACHE_DIM
;   Protected i = ImageID(hPatternImage)
;   
;   For x = 0 To w Step #GRID_PATTERN_CACHE_DIM
;     For y = 0 To h Step #GRID_PATTERN_CACHE_DIM
;       MovePathCursor(x, y)
;       DrawVectorImage(i)
;     Next y 
;   Next x 
; EndProcedure

Procedure DrawGridPattern(hPatternImage)
  VectorSourceImage(ImageID(hPatternImage), 255, #GRID_PATTERN_CACHE_DIM, #GRID_PATTERN_CACHE_DIM, #PB_VectorImage_Repeat)
  FillVectorOutput()
EndProcedure

Procedure Max(a.i, b.i)
  If (a > b)
    ProcedureReturn a
  EndIf 
  
  ProcedureReturn b
EndProcedure

Procedure Min(a.i, b.i)
  If (a < b)
    ProcedureReturn a
  EndIf 
  
  ProcedureReturn b
EndProcedure

; Create a key-value pair for the on-screen debugging information.
Macro __debug_kvpair(k,v)
  AddElement(Keys())
  Keys() = k
  AddElement(Values())
  Values() = v
EndMacro

; Create a header for the on-screen debugging information.
Macro __debug_header(h)
  __debug_kvpair(h, "----")
EndMacro

; Create an empty line for the on-screen debugging information.
Macro __debug_empty()
  __debug_kvpair("####", "####")
EndMacro

; Render the on-screen debugging information, if enabled.
Procedure DrawDebugInfo(*CanvasImageState.CanvasImageState)
  If (Not *CanvasImageState\DInfo\ShowDebugInfo)
    ProcedureReturn ; Debugging information not enabled.
  EndIf 
  
  Protected NewList Keys.s()
  Protected NewList Values.s() ; if value == ---- then the key is a header, #### for both means an empty line
  
  With *CanvasImageState\DInfo
    __debug_header("Timings")
    __debug_kvpair("Load Time", Str(\ImageLoadTime) + "ms")
    __debug_kvpair("Draw Time", Str(\PreviousRenderTime) + "ms")
    __debug_empty()
    
    __debug_header("Image")
    __debug_kvpair("Original Size", Str(\ImageWidth) + "x" + Str(\ImageHeight) + "px")
    __debug_kvpair("Original Depth", Str(\ImageDepth))
    __debug_kvpair("Zoom Level", Str(\ZoomLevel) + "%")
    __debug_kvpair("Current Size", Str(\CurrentImageWidth) + "x" + Str(\CurrentImageHeight) + "px")
    __debug_kvpair("Rendered Depth", Str(\ImageRenderedDepth)) 
    __debug_empty()
    
    __debug_header("Offsets")
    __debug_kvpair("X-Offset", Str(\XOffset) + "px")
    __debug_kvpair("Y-Offset", Str(\YOffset) + "px")
  EndWith
  
  VectorFont(FontID(hDebugFont))
  
  Protected boxOffset = 5
  Protected textPadding = 5
  Protected maximumKeyWidth, maximumValueWidth
  Protected maximumHeight
  
  ForEach (Keys())
    SelectElement(Values(), ListIndex(Keys()))
    
    maximumKeyWidth   = Max(VectorTextWidth(Keys() + ": "), maximumKeyWidth)
    maximumValueWidth = Max(VectorTextWidth(Values()), maximumValueWidth)
    maximumHeight     = Max(VectorTextHeight(Keys()), Max(VectorTextHeight(Values()), maximumHeight))
  Next 
  
  Protected boxWidth = maximumKeyWidth + maximumValueWidth + (textPadding * 2)
  Protected boxHeight = ((maximumHeight + textPadding) * ListSize(Keys())) + textPadding
  
  AddPathBox(boxOffset, boxOffset, boxWidth, boxHeight)
  VectorSourceColor(RGBA(0, 0, 0, 200))
  FillPath(#PB_Path_Preserve)
  VectorSourceColor(RGBA(255, 255, 255, 200))
  StrokePath(1)
  
  Protected textX = boxOffset + textPadding
  Protected textY = boxOffset + textPadding
  Protected textO
  Protected key.s, value.s
  
  ForEach (Keys())
    SelectElement(Values(), ListIndex(Keys()))
    
    key = Keys()
    value = Values()
    
    If (value = "----")
      textO = (boxWidth / 2) - (VectorTextWidth(key) / 2)
      MovePathCursor(textX + textO, textY)
      DrawVectorText(key)
      textY + maximumHeight + textPadding
    ElseIf (value = "####" And key = "####")
      textY + maximumHeight + textPadding
    Else 
      MovePathCursor(textX, textY)
      DrawVectorText(key + ": ")
      MovePathCursor(textX + maximumKeyWidth, textY)
      DrawVectorText(value)
      textY + maximumHeight + textPadding
    EndIf 
  Next 
EndProcedure

; redraw the canvas.
; canvas: the canvas gadget with the CanvasImageState data.
Procedure RedrawCanvas(canvas)
  Static hPatternImage = #Null 
  If (hPatternImage = #Null)
    ; the pattern image was not created yet, prepare it.
    hPatternImage = CreateImage(#PB_Any, #GRID_PATTERN_CACHE_DIM, #GRID_PATTERN_CACHE_DIM, 32)
    If (Not hPatternImage)
      UiError("Pattern Error", "Cannot prepare canvas background pattern, program terminating.")
    EndIf 
    
    If (StartDrawing(ImageOutput(hPatternImage)))
      Box(0, 0, OutputWidth(), OutputHeight(), RGBA(255, 255, 255, 255))
      DrawingMode(#PB_2DDrawing_CustomFilter)
      CustomFilterCallback(@GridPatternCallback())
      Box(0, 0, OutputWidth(), OutputHeight(), RGBA(230, 230, 230, 255))
      StopDrawing()
    EndIf
  EndIf 
  
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(canvas)
  
  If (StartVectorDrawing(CanvasVectorOutput(canvas, #PB_Unit_Pixel)))
    Protected b = ElapsedMilliseconds()
    Protected w = VectorOutputWidth()
    Protected h = VectorOutputHeight()
    
    ; clear the canvas by drawing the background pattern.
    DrawGridPattern(hPatternImage)
    
    With *CanvasImageState
      If (IsImage(\hZoomedImage))
        Protected z.f = \ZoomLevel / 100.0                ; zoom factor
;         Protected ziw = ImageWidth(\hZoomedImage) * z     ; scaled width
;         Protected zih = ImageHeight(\hZoomedImage) * z    ; scaled height
        Protected ziw = ImageWidth(\hZoomedImage)     ; scaled width
        Protected zih = ImageHeight(\hZoomedImage)    ; scaled height
        Protected zix = ((w / 2) - (ziw / 2) + \XOffset)  ; x coordinate (center + x offset)
        Protected ziy = ((h / 2) - (zih / 2) + \YOffset)  ; x coordinate (center + y offset)
        
        ; first move to the correct coordinates 
        MovePathCursor(zix, ziy)
        
        ; we scale to the zoom level of the image
        ; ScaleCoordinates(z, z)
        
        ; render the image, PureBasic's vector system will handle the size
        DrawVectorImage(ImageID(\hZoomedImage))
        
        ; restore coordinates
        ; ScaleCoordinates(1.0, 1.0)
      EndIf 
      
      \DInfo\PreviousRenderTime = ElapsedMilliseconds() - b
    EndWith
    
    DrawDebugInfo(*CanvasImageState)
    
    StopVectorDrawing()
  EndIf 
EndProcedure

; Zoom the current state.
Procedure ZoomCanvas(canvas, zstep, absolute = #False)
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(canvas)
  
  With *CanvasImageState
    If (Not IsImage(\hCurrentlyLoadedImage))
      ProcedureReturn
    EndIf 
    
    If (absolute)
      \ZoomLevel = zstep
    Else 
      \ZoomLevel + zstep 
    EndIf 
    
    If (\ZoomLevel < 1)
      \ZoomLevel = 1
    EndIf 
    
    If (\ZoomLevel > 1000)
      \ZoomLevel = 1000
    EndIf
    
    If (IsImage(\hZoomedImage))
      FreeImage(\hZoomedImage)
    EndIf 
    
    \hZoomedImage = CopyImage(\hCurrentlyLoadedImage, #PB_Any)
    If (Not \hZoomedImage)
      UiError("Zoom Error", "Cannot zoom the image for unknown reasons, do you have enough RAM left? Program terminating.")
    EndIf 
    
    Protected z.f = \ZoomLevel / 100.0
    ResizeImage(\hZoomedImage, ImageWidth(\hZoomedImage) * z, ImageHeight(\hZoomedImage) * z, #PB_Image_Raw)
    
    \DInfo\ZoomLevel          = \ZoomLevel
    \DInfo\CurrentImageWidth  = ImageWidth(\hZoomedImage)
    \DInfo\CurrentImageHeight = ImageHeight(\hZoomedImage)
  EndWith
  
  RedrawCanvas(canvas)
EndProcedure

; handles the window resizing.
; the canvas is resized to fit the window and the current state is rendered again.
Procedure HandleResizeEvent()
  ResizeGadget(hCanvas, #PB_Ignore, #PB_Ignore, WindowWidth(hWindow), WindowHeight(hWindow) - MenuHeight())
  RedrawCanvas(hCanvas)
EndProcedure

; handle the open file action.
Procedure HandleOpenFile()
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(hCanvas)
  Protected pattern.s = #FILE_DIALOG_QOI_PATTERN + "|" + #FILE_DIALOG_IMG_PATTERN + "|" + #FILE_DIALOG_ALL_PATTERN
  Protected filePath.s = OpenFileRequester("Select Image File", "", pattern, 0)
  
  If (filePath = "")
    ProcedureReturn
  EndIf 
  
  Protected s = ElapsedMilliseconds()
  Protected hImage = LoadImage(#PB_Any, filePath)
  
  If (Not hImage)
    MessageRequester("Cannot Load Image", "The selected file cannot be loaded, is it one of the supported formats?", #PB_MessageRequester_Error)
    ProcedureReturn
  EndIf 
  
  With *CanvasImageState\DInfo
    \ImageLoadTime      = ElapsedMilliseconds() - s
    \ImageWidth         = ImageWidth(hImage)
    \ImageHeight        = ImageHeight(hImage)
    \ImageDepth         = ImageDepth(hImage, #PB_Image_OriginalDepth)
    \ImageRenderedDepth = ImageDepth(hImage, #PB_Image_InternalDepth)
    \ZoomLevel          = 100
    \CurrentImageWidth  = \ImageWidth
    \CurrentImageHeight = \ImageHeight
  EndWith
  
  With *CanvasImageState
    If (IsImage(\hCurrentlyLoadedImage))
      FreeImage(\hCurrentlyLoadedImage)
      FreeImage(\hZoomedImage)
    EndIf 
    
    \hCurrentlyLoadedImage = hImage
    \hZoomedImage = CopyImage(hImage, #PB_Any)
    \ZoomLevel = 100
    \XOffset = 0
    \YOffset = 0
  EndWith
  
  DisableMenuItem(hMenu, #MENU_ACTION_FILE_SAVE_AS, #False)
  For i = #MENU_ACTION_VIEW_RESET_OFFSET To #MENU_ACTION_VIEW_ZOOM_SUB
    DisableMenuItem(hMenu, i, #False)
  Next i
  
  RedrawCanvas(hCanvas)
EndProcedure

; handle the save as action
Procedure HandleSaveFileAs()
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(hCanvas)
  If (Not IsImage(*CanvasImageState\hCurrentlyLoadedImage))
    ProcedureReturn ; nothing to save
  EndIf 
  
  Protected pattern.s = #FILE_DIALOG_QOI_PATTERN + "|" + #FILE_DIALOG_ALL_PATTERN
  Protected filePath.s = SaveFileRequester("Save As QOI", "", pattern, 0)
 
  If (filePath = "")
    ProcedureReturn ; cancelled
  EndIf 
  
  If (FileSize(filePath) >= 0)
    Protected answer = MessageRequester("File Exists", "The file you selected already exists, do you want to overwrite?", #PB_MessageRequester_YesNo | #PB_MessageRequester_Warning)
    If (answer <> #PB_MessageRequester_Yes)
      ProcedureReturn
    EndIf 
  EndIf 
  
  If (Not SaveImage(*CanvasImageState\hCurrentlyLoadedImage, filePath, #PB_ImagePlugin_QOI))
    MessageRequester("Error", "Saving the image as QOI failed, do you have appropriate access in the selected directory?", #PB_MessageRequester_Error)
  EndIf 
EndProcedure

; handle the exit action
Procedure HandleExit()
  Quit = #True 
EndProcedure

; handle the debugging info toggle action.
Procedure HandleToggleDebugInfo()
  Protected state = Bool(Not GetMenuItemState(hMenu, #MENU_ACTION_VIEW_DEBUG))
  SetMenuItemState(hMenu, #MENU_ACTION_VIEW_DEBUG, state)
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(hCanvas)
  *CanvasImageState\DInfo\ShowDebugInfo = state
  RedrawCanvas(hCanvas)
EndProcedure

; handle the canvas wheel event
Procedure HandleCanvasZoom()
  Protected canvas = EventGadget()
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(canvas)
  Protected delta = GetGadgetAttribute(canvas, #PB_Canvas_WheelDelta)
  Protected zstep = #GRID_ZOOM_STEP
  If (delta < 0)
    zstep = -#GRID_ZOOM_STEP
  EndIf 
  
  ZoomCanvas(canvas, zstep)
EndProcedure

; handle the canvas mouse move event
Procedure HandleCanvasMove()
  Protected canvas = EventGadget()
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(canvas)
  
  With *CanvasImageState
    If (\Mouse\LeftMouseDown And IsImage(\hCurrentlyLoadedImage))
      \Mouse\XCurrent = GetGadgetAttribute(canvas, #PB_Canvas_MouseX)
      \Mouse\YCurrent = GetGadgetAttribute(canvas, #PB_Canvas_MouseY)
      
      \XOffset = \Mouse\XOffset + \Mouse\XCurrent - \Mouse\XStart
      \YOffset = \Mouse\YOffset + \Mouse\YCurrent - \Mouse\YStart
      
      \DInfo\XOffset = \XOffset
      \DInfo\YOffset = \YOffset
      
      RedrawCanvas(canvas)
    EndIf 
  EndWith
EndProcedure

; handle the application wide escape key event
Procedure HandleCanvasCancelMove()
  Protected canvas = hCanvas
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(canvas)
  
  With *CanvasImageState
    If (\Mouse\LeftMouseDown)
      \Mouse\LeftMouseDown = #False 
      \XOffset = \Mouse\XOffset
      \YOffset = \Mouse\YOffset
      
      RedrawCanvas(canvas)
    EndIf 
  EndWith
EndProcedure

; handle the offset reset action by re-aligning the image to the center.
Procedure HandleResetOffset()
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(hCanvas)
  With *CanvasImageState
    \Mouse\LeftMouseDown = #False 
    \Mouse\XOffset = 0
    \Mouse\YOffset = 0
    \DInfo\XOffset = 0
    \DInfo\YOffset = 0
    \XOffset = 0
    \YOffset = 0
  EndWith
  
  RedrawCanvas(hCanvas)
EndProcedure

; handle the reset zoom action by zooming back to 100%.
Procedure HandleResetZoom()
  ZoomCanvas(hCanvas, 100, #True)
EndProcedure

; handle the zoom in action by adding GRID_ZOOM_STEP to the current zoom level.
Procedure HandleAddZoom()
  ZoomCanvas(hCanvas, #GRID_ZOOM_STEP, #False)
EndProcedure

; handle the zoom in action by subtracting GRID_ZOOM_STEP from the current zoom level.
Procedure HandleSubZoom()
  ZoomCanvas(hCanvas, -#GRID_ZOOM_STEP, #False)
EndProcedure

; handle the mouse down event (start moving)
Procedure HandleCanvasMouseDown()
  Protected canvas = EventGadget()
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(canvas)
  
  With *CanvasImageState
    \Mouse\LeftMouseDown = #True 
    \Mouse\XStart = GetGadgetAttribute(canvas, #PB_Canvas_MouseX)
    \Mouse\YStart = GetGadgetAttribute(canvas, #PB_Canvas_MouseY)
    \Mouse\XOffset = \XOffset
    \Mouse\YOffset = \YOffset
  EndWith
EndProcedure

; handle the mouse up event (stop moving)
Procedure HandleCanvasMouseUp() 
  Protected canvas = EventGadget()
  Protected *CanvasImageState.CanvasImageState = GetGadgetData(canvas)
  *CanvasImageState\Mouse\LeftMouseDown = #False 
EndProcedure

; Create the main application window.
hWindow = OpenWindow(#PB_Any, 0, 0, 500, 300, #WINDOW_TITLE, #WINDOW_FLAGS)
If (Not hWindow)
  UiError("Window Error", "Cannot open main window, terminating program")
EndIf 

If (Not hWindow)
  UiError("UI Error", "Can not open window, program terminating.")
EndIf 

hMenu = CreateMenu(#PB_Any, WindowID(hWindow))

If (Not hMenu)
  UiError("Menu Error", "Can not instantiate menu, program terminating.")
EndIf 

MenuTitle("File")
  MenuItem(#MENU_ACTION_FILE_OPEN, "Open"    + Chr(9) + #SHORTCUT_MODIFIER_STRING + "+O")
  MenuItem(#MENU_ACTION_FILE_SAVE_AS, "Save as" + Chr(9) + #SHORTCUT_MODIFIER_STRING + "+S")
  MenuBar()
  MenuItem(#MENU_ACTION_FILE_CLOSE, "Close"   + Chr(9) + #SHORTCUT_CLOSE_MOD_STRING + "+" + #SHORTCUT_CLOSE_STRING)
  
MenuTitle("View")
  MenuItem(#MENU_ACTION_VIEW_DEBUG, "Show Debug Info" + Chr(9) + #SHORTCUT_MODIFIER_STRING+"+D")
  MenuBar()
  MenuItem(#MENU_ACTION_VIEW_RESET_OFFSET, "Reset Offset" + Chr(9) + #SHORTCUT_MODIFIER_STRING+"+R")
  MenuItem(#MENU_ACTION_VIEW_RESET_ZOOM, "Reset Zoom" + Chr(9) + #SHORTCUT_MODIFIER_STRING+"+0")
  MenuItem(#MENU_ACTION_VIEW_ZOOM_ADD, "Zoom +" + Chr(9) + #SHORTCUT_MODIFIER_STRING+"++")
  MenuItem(#MENU_ACTION_VIEW_ZOOM_SUB, "Zoom -" + Chr(9) + #SHORTCUT_MODIFIER_STRING+"+-")
  
AddKeyboardShortcut(hWindow, #SHORTCUT_MODIFIER_KEY | #PB_Shortcut_O, #MENU_ACTION_FILE_OPEN)
AddKeyboardShortcut(hWindow, #SHORTCUT_MODIFIER_KEY | #PB_Shortcut_S, #MENU_ACTION_FILE_SAVE_AS)
AddKeyboardShortcut(hWindow, #SHORTCUT_CLOSE_MOD_KEY | #SHORTCUT_CLOSE_KEY, #MENU_ACTION_FILE_CLOSE)

AddKeyboardShortcut(hWindow, #SHORTCUT_MODIFIER_KEY | #PB_Shortcut_D, #MENU_ACTION_VIEW_DEBUG)
AddKeyboardShortcut(hWindow, #SHORTCUT_MODIFIER_KEY | #PB_Shortcut_R, #MENU_ACTION_VIEW_RESET_OFFSET)
AddKeyboardShortcut(hWindow, #SHORTCUT_MODIFIER_KEY | #PB_Shortcut_0, #MENU_ACTION_VIEW_RESET_ZOOM)
AddKeyboardShortcut(hWindow, #SHORTCUT_MODIFIER_KEY | #PB_Shortcut_Pad0, #MENU_ACTION_VIEW_RESET_ZOOM)
AddKeyboardShortcut(hWindow, #SHORTCUT_MODIFIER_KEY | #PB_Shortcut_Add, #MENU_ACTION_VIEW_ZOOM_ADD)
AddKeyboardShortcut(hWindow, #SHORTCUT_MODIFIER_KEY | #PB_Shortcut_Subtract, #MENU_ACTION_VIEW_ZOOM_SUB)

AddKeyboardShortcut(hWindow, #PB_Shortcut_Escape, #MENU_ACTION_CANCEL_MOVE)

hCanvas = CanvasGadget(#PB_Any, 0, 0, WindowWidth(hWindow), WindowHeight(hWindow) - MenuHeight())
If (Not hCanvas)
  UiError("Canvas Error", "Can not instantiate the rendering area for loaded images, program terminated.")
EndIf 

SetGadgetData(hCanvas, CanvasImageState)
RedrawCanvas(hCanvas)

SmartWindowRefresh(hWindow, #True)
BindEvent(#PB_Event_SizeWindow, @HandleResizeEvent(), hWindow)
BindEvent(#PB_Event_CloseWindow, @HandleExit(), hWindow)

BindMenuEvent(hMenu, #MENU_ACTION_FILE_OPEN, @HandleOpenFile())
BindMenuEvent(hMenu, #MENU_ACTION_FILE_SAVE_AS, @HandleSaveFileAs())
BindMenuEvent(hMenu, #MENU_ACTION_FILE_CLOSE, @HandleExit())
BindMenuEvent(hMenu, #MENU_ACTION_VIEW_DEBUG, @HandleToggleDebugInfo())
BindMenuEvent(hMenu, #MENU_ACTION_VIEW_RESET_OFFSET, @HandleResetOffset())
BindMenuEvent(hMenu, #MENU_ACTION_VIEW_RESET_ZOOM, @HandleResetZoom())
BindMenuEvent(hMenu, #MENU_ACTION_VIEW_ZOOM_ADD, @HandleAddZoom())
BindMenuEvent(hMenu, #MENU_ACTION_VIEW_ZOOM_SUB, @HandleSubZoom())
BindMenuEvent(hMenu, #MENU_ACTION_CANCEL_MOVE, @HandleCanvasCancelMove())

BindGadgetEvent(hCanvas, @HandleCanvasZoom(), #PB_EventType_MouseWheel)
BindGadgetEvent(hCanvas, @HandleCanvasMove(), #PB_EventType_MouseMove)
BindGadgetEvent(hCanvas, @HandleCanvasMouseDown(), #PB_EventType_LeftButtonDown)
BindGadgetEvent(hCanvas, @HandleCanvasMouseUp(), #PB_EventType_LeftButtonUp)

DisableMenuItem(hMenu, #MENU_ACTION_FILE_SAVE_AS, #True)
For i = #MENU_ACTION_VIEW_RESET_OFFSET To #MENU_ACTION_VIEW_ZOOM_SUB
  DisableMenuItem(hMenu, i, #True)
Next i

; window event loop
Repeat : WaitWindowEvent() : Until Quit

CloseWindow(hWindow)
; IDE Options = PureBasic 6.00 Beta 5 - C Backend (MacOS X - arm64)
; CursorPosition = 563
; FirstLine = 547
; Folding = -----
; EnableXP