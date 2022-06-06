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

; Automated test application. This application will try to load all images
; in a test directory and convert them to QOI. It will measure the time it 
; takes to do the conversion and it will also verify that the color data 
; matches with the original input after decoding the QOI image again.

XIncludeFile "QoiImagePlugin.pbi"

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

#TEST_STATUS_GOOD = "GOOD"
#TEST_STATUS_FAIL = "FAIL"
#TEST_STATUS_INFO = "INFO"
#TEST_STATUS_WARN = "WARN"
#TEST_DIRECTORY   = "test"

CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  #DIRECTORY_SEPARATOR = "\"
CompilerElse
  #DIRECTORY_SEPARATOR = "/"
CompilerEndIf 

Prototype ColorAccuracyTest(*ColorAccuracyTestDesc)

Structure ColorAccuracyTestDescriptor
  name.s
  desc.s
  bits.i
  width.i
  height.i
  transparent.i
  test.ColorAccuracyTest
EndStructure

Global NewMap Extensions.i()
Global NewList ColorAccuracyTests.ColorAccuracyTestDescriptor()

Macro AddColorAccuracyTest(_name, _desc, _bits, _width, _height, _transparent, _test)
  AddElement(ColorAccuracyTests())
  ColorAccuracyTests()\name = _name
  ColorAccuracyTests()\desc = _desc
  ColorAccuracyTests()\bits = _bits
  ColorAccuracyTests()\width = _width
  ColorAccuracyTests()\height = _height
  ColorAccuracyTests()\transparent = _transparent
  ColorAccuracyTests()\test = _test
EndMacro

Extensions("png") = #True 
Extensions("jpg") = #True 
Extensions("jpeg") = #True 
Extensions("jp2") = #True 
Extensions("jfif") = #True 
Extensions("bmp") = #True 
Extensions("tga") = #True 
Extensions("tif") = #True 
Extensions("tiff") = #True 
Extensions("gif") = #True 
Extensions("ico") = #True 
Extensions("cur") = #True 

Procedure GetImageData(hImage)
  Protected *result = #Null 
  If (StartDrawing(ImageOutput(hImage)))
    Protected *buffer = DrawingBuffer()
    Protected pitch   = DrawingBufferPitch()
    Protected height  = OutputHeight()
    
    If (Not *buffer)
      StopDrawing()
      ProcedureReturn *result 
    EndIf 
    
    *result = AllocateMemory(height * pitch)
    If (*result)
      CopyMemory(*buffer, *result, height * pitch)
    EndIf 
    
    StopDrawing()
  EndIf 
  ProcedureReturn *result
EndProcedure

Procedure CompareImageData(hImage1, hImage2) 
  Protected *buffer1 = GetImageData(hImage1)
  If (Not *buffer1)
    ProcedureReturn -1
  EndIf 
  
  Protected *buffer2 = GetImageData(hImage2)
  If (Not *buffer2)
    FreeMemory(*buffer1)
    ProcedureReturn -1
  EndIf 
  
  Protected result = Bool(MemorySize(*buffer1) = MemorySize(*buffer2))
  If (result)
    result = CompareMemory(*buffer1, *buffer2, MemorySize(*buffer1))
  EndIf 
  
  FreeMemory(*buffer1)
  FreeMemory(*buffer2)
  
  ProcedureReturn result 
EndProcedure

Macro TEST_GOOD(s)
  ConsoleColor(2, 0)
  Print("[" + #TEST_STATUS_GOOD + "] ")
  ConsoleColor(7, 0)
  PrintN(s)
EndMacro

Macro TEST_FAIL(s)
  ConsoleColor(4, 0)
  Print("[" + #TEST_STATUS_FAIL + "] ")
  ConsoleColor(7, 0)
  PrintN(s)
EndMacro

Macro TEST_FAIL_END(s)
  TEST_FAIL(s)
  End 1
EndMacro

Macro TEST_INFO(s)
  ConsoleColor(3, 0)
  Print("[" + #TEST_STATUS_INFO + "] ")
  ConsoleColor(11, 0)
  PrintN(s)
  ConsoleColor(7, 0)
EndMacro

Macro TEST_WARN(s)
  ConsoleColor(6, 0)
  Print("[" + #TEST_STATUS_WARN + "] ")
  ConsoleColor(14, 0)
  PrintN(s)
  ConsoleColor(7, 0)
EndMacro

Procedure.s CombinePath(p1.s, p2.s)
  If (Right(p1, 1) <> #DIRECTORY_SEPARATOR)
    p1 + #DIRECTORY_SEPARATOR
  EndIf 
  
  ProcedureReturn p1 + p2
EndProcedure

Procedure GetFileList(path.s, List filepaths.s())
  Protected hDirectory = ExamineDirectory(#PB_Any, path, "*.*")
  If (Not hDirectory)
    TEST_FAIL_END("Cannot examine directory: " + path + ".")
  EndIf 
  
  While (NextDirectoryEntry(hDirectory))
    Protected name.s = DirectoryEntryName(hDirectory)
    Protected entr.s = CombinePath(path, name)
    Protected exts.s = GetExtensionPart(entr)
    
    Select DirectoryEntryType(hDirectory)
      Case #PB_DirectoryEntry_File
        If (Not FindMapElement(Extensions(), LCase(exts)))
          Continue 
        EndIf 
        
        AddElement(filepaths())
        filepaths() = entr
      Case #PB_DirectoryEntry_Directory
        If (name = "." Or name = "..")
          Continue 
        EndIf 
        
        GetFileList(entr, filepaths())
    EndSelect
  Wend 
  
  FinishDirectory(hDirectory)
EndProcedure

Procedure TestImage(filepath.s)
  If (FileSize(filepath) < 0)
    TEST_FAIL("File does not exist: " + filepath)
    ProcedureReturn #False 
  EndIf 
  
  Protected hImageOriginal = LoadImage(#PB_Any, filepath)
  If (Not hImageOriginal)
    TEST_FAIL("Cannot decode image: " + filepath)
    ProcedureReturn #False 
  EndIf 
  
  Protected *lpImageQoiEncoded = EncodeImage(hImageOriginal, #PB_ImagePlugin_QOI)
  If (Not *lpImageQoiEncoded)
    TEST_FAIL("Canot encode image as QOI: " + filepath)
    FreeImage(hImageOriginal)
    ProcedureReturn #False 
  EndIf
  
  Protected hImageReloaded = CatchImage(#PB_Any, *lpImageQoiEncoded, MemorySize(*lpImageQoiEncoded))
  If (Not hImageReloaded)
    TEST_FAIL("Cannot reload image as QOI: " + filepath)
    FreeImage(hImageOriginal)
    FreeMemory(*lpImageQoiEncoded)
    ProcedureReturn #False 
  EndIf 
  
  Protected result = CompareImageData(hImageOriginal, hImageReloaded)
  FreeImage(hImageOriginal)
  FreeImage(hImageReloaded)
  FreeMemory(*lpImageQoiEncoded)
  
  Protected filename.s = GetFilePart(filepath)
  
  If (result)
    TEST_GOOD("Decode from original -> encode to QOI -> decode -> compare: " + filename)
  Else
    TEST_FAIL("Decode from original -> encode to QOI -> decode -> compare: " + filename)
  EndIf 
  
  ProcedureReturn result 
EndProcedure

;{
;-[Color Accuracy Tests]

#CAT_TEST_SQUARE_DIMENSION = 400
#CAT_TEST_RECT_DIMENSION1  = 800
#CAT_TEST_RECT_DIMENSION2  = 300
#CAT_TEST_CIRCLE_RADIUS    = 50
#CAT_TEST_INNER_RECT_SIZE  = 60

Procedure CAT_RGBA(*ColorAccuracyTest.ColorAccuracyTestDescriptor, r.i, g.i, b.i, a.i = 255)
  If (*ColorAccuracyTest\bits = 32)
    ProcedureReturn RGBA(r, g, b, a)
  EndIf 
  
  ProcedureReturn RGB(r, g, b)
EndProcedure

Procedure CAT_Test_Dynamic(*ColorAccuracyTest.ColorAccuracyTestDescriptor)
  Protected bg
  If (*ColorAccuracyTest\transparent And *ColorAccuracyTest\bits = 32)
    bg = #PB_Image_Transparent
  Else
    bg = CAT_RGBA(*ColorAccuracyTest, 255, 255, 255)
  EndIf 
  
  Protected result = #True 
  Protected hImage = CreateImage(#PB_Any, *ColorAccuracyTest\width, *ColorAccuracyTest\height, *ColorAccuracyTest\bits, bg)
  If (Not hImage)
    TEST_FAIL_END("Cannot initialize image for `" + *ColorAccuracyTest\name + "`, terminating...")
  EndIf 
  
  If (StartDrawing(ImageOutput(hImage)))
    If (*ColorAccuracyTest\bits = 32)
      DrawingMode(#PB_2DDrawing_AlphaBlend)
    EndIf 
    
    If (Not *ColorAccuracyTest\transparent And *ColorAccuracyTest\bits = 32)
      Box(0, 0, OutputWidth(), OutputHeight(), cat_rgba(*ColorAccuracyTest, 255, 255, 255))
    EndIf 
    
    ; Left top corner
    Box(0, 0, #CAT_TEST_INNER_RECT_SIZE, #CAT_TEST_INNER_RECT_SIZE, CAT_RGBA(*ColorAccuracyTest, 255, 0, 0))
    
    ; Right top corner 
    Box(OutputWidth() - #CAT_TEST_INNER_RECT_SIZE, 0, #CAT_TEST_INNER_RECT_SIZE, #CAT_TEST_INNER_RECT_SIZE, CAT_RGBA(*ColorAccuracyTest, 120, 33, 15))
    
    ; Right bottom corner
    Box(OutputWidth() - #CAT_TEST_INNER_RECT_SIZE, OutputHeight() - #CAT_TEST_INNER_RECT_SIZE, #CAT_TEST_INNER_RECT_SIZE, #CAT_TEST_INNER_RECT_SIZE, CAT_RGBA(*ColorAccuracyTest, 0, 200, 111))
    
    ; Left bottom corner - slightly transparent
    Box(0, OutputHeight() - #CAT_TEST_INNER_RECT_SIZE, #CAT_TEST_INNER_RECT_SIZE, #CAT_TEST_INNER_RECT_SIZE, CAT_RGBA(*ColorAccuracyTest, 17, 155, 277, 200))
    
    ; Circle in the center - slightly transparent
    Circle(OutputWidth() / 2, OutputHeight() / 2, #CAT_TEST_CIRCLE_RADIUS, CAT_RGBA(*ColorAccuracyTest, 1, 2, 3, 150))
    
    StopDrawing()
  EndIf 

  Protected *encoded = EncodeImage(hImage, #PB_ImagePlugin_QOI)
  If (Not *encoded)
    FreeImage(hImage)
    TEST_FAIL_END("Cannot encode QOI for `" + *ColorAccuracyTest\name + "`, terminating...")
  EndIf 
  
  Protected hDecodedImage = CatchImage(#PB_Any, *encoded)
  If (Not hDecodedImage)
    FreeMemory(*encoded)
    FreeImage(hImage)
    TEST_FAIL_END("Cannot decode QOI for `" + *ColorAccuracyTest\name + "`, terminating...")
  EndIf 
  
  result = CompareImageData(hImage, hDecodedImage)
  
  FreeImage(hDecodedImage)
  FreeMemory(*encoded)
  FreeImage(hImage)
  
  ProcedureReturn result 
EndProcedure

AddColorAccuracyTest("24-bit opaque square", "A 24-bit square", 24, #CAT_TEST_SQUARE_DIMENSION, #CAT_TEST_SQUARE_DIMENSION, #False, @CAT_Test_Dynamic())
AddColorAccuracyTest("24-bit opaque rectangle 1", "A 24-bit rectangle with long X", 24, #CAT_TEST_RECT_DIMENSION1, #CAT_TEST_RECT_DIMENSION2, #False, @CAT_Test_Dynamic())
AddColorAccuracyTest("24-bit opaque rectangle 2", "A 24-bit rectangle with long Y", 24, #CAT_TEST_RECT_DIMENSION2, #CAT_TEST_RECT_DIMENSION1, #False, @CAT_Test_Dynamic())

AddColorAccuracyTest("32-bit opaque square", "A 32-bit square", 32, #CAT_TEST_SQUARE_DIMENSION, #CAT_TEST_SQUARE_DIMENSION, #False, @CAT_Test_Dynamic())
AddColorAccuracyTest("32-bit opaque rectangle 1", "A 32-bit rectangle with long X", 32, #CAT_TEST_RECT_DIMENSION1, #CAT_TEST_RECT_DIMENSION2, #False, @CAT_Test_Dynamic())
AddColorAccuracyTest("32-bit opaque rectangle 2", "A 32-bit rectangle with long Y", 32, #CAT_TEST_RECT_DIMENSION2, #CAT_TEST_RECT_DIMENSION1, #False, @CAT_Test_Dynamic())

AddColorAccuracyTest("32-bit transparent square", "A 32-bit square", 32, #CAT_TEST_SQUARE_DIMENSION, #CAT_TEST_SQUARE_DIMENSION, #True, @CAT_Test_Dynamic())
AddColorAccuracyTest("32-bit transparent rectangle 1", "A 32-bit rectangle With long X", 32, #CAT_TEST_RECT_DIMENSION1, #CAT_TEST_RECT_DIMENSION2, #True, @CAT_Test_Dynamic())
AddColorAccuracyTest("32-bit transparent rectangle 2", "A 32-bit rectangle with long Y", 32, #CAT_TEST_RECT_DIMENSION2, #CAT_TEST_RECT_DIMENSION1, #True, @CAT_Test_Dynamic())

;}

Procedure Main()
  CompilerIf #PB_Compiler_Debugger
    TEST_WARN("Notice that the test is being run in debug mode.")
    TEST_WARN("The speed of the encoder/decoder will be drastically")
    TEST_WARN("reduced from a release build of the same code.")
  CompilerEndIf 
  
  TEST_INFO("Testing decode -> encode -> decode of images in `" + #TEST_DIRECTORY + "`")
  Protected NewList filepaths.s()
  GetFileList(#TEST_DIRECTORY, filepaths())
  
  ForEach (filepaths())
    TestImage(filepaths())
  Next 
  
  TEST_INFO("Testing color accuracy from render to decode")
  
  Protected cat_test_name.s
  Protected cat_test_desc.s
  Protected cat_test_dims.s
  
  ForEach (ColorAccuracyTests())
    With ColorAccuracyTests()
      cat_test_name = \name
      cat_test_desc = \desc
      cat_test_dims = Str(\width) + "x" + Str(\height) + "x" + Str(\bits)
    EndWith
  
    If (ColorAccuracyTests()\test(ColorAccuracyTests()))
      TEST_GOOD("Test `" + cat_test_name + "` (" + cat_test_desc + ") at " + cat_Test_dims + " succeeded")
    Else 
      TEST_FAIL("Test `" + cat_test_name + "` (" + cat_test_desc + ") at " + cat_Test_dims + " failed")
    EndIf 
  Next 
EndProcedure

If (Not OpenConsole("QOI Codec Test"))
  End 2
EndIf 

Main()
; IDE Options = PureBasic 6.00 Beta 5 - C Backend (MacOS X - arm64)
; CursorPosition = 20
; FirstLine = 9
; Folding = ---
; EnableXP