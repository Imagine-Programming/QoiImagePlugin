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

; Define a macro for the appropriate calling convention
CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  Macro QOI_ProcedureI : Procedure : EndMacro
CompilerElse
  Macro QOI_ProcedureI : ProcedureC : EndMacro
CompilerEndIf 

; encoder/decoder flags
#QOI_ImageDecoder_File     = 0 ; image should be en-/decoded to/from file
#QOI_ImageDecoder_Memory   = 1 ; image should be en-/decoded to/from buffer
#QOI_ImageDecoder_ReverseY = 2 ; y-coordinate should be reversed

; The decoder definition
Structure QOI_ImageDecoder Align #PB_Structure_AlignC
  *Check
  *Decode
  *Cleanup
  ID.l
EndStructure

; The decoder state
Structure QOI_ImageDecoderGlobals Align #PB_Structure_AlignC
  *Decoder.QOI_ImageDecoder
  *Filename
  *File
  *Buffer
  Length.l
  Mode.l
  Width.l
  Height.l
  Depth.l
  Flags.l
  Data.i[8]
  OriginalDepth.l
EndStructure

; The encoder definition
Structure QOI_ImageEncoder Align #PB_Structure_AlignC
  ID.l
  *Encode24
  *Encode32
EndStructure

IsImage(0) ; Ensure image library is present

; Import ImageDecoder_Register and ImageEncoder_Register
CompilerIf #PB_Compiler_OS = #PB_OS_Windows And #PB_Compiler_Processor = #PB_Processor_x86  
  Import ""
    QOI_ImageDecoder_Register(*ImageDecoder.QOI_ImageDecoder) As "_PB_ImageDecoder_Register@4"
    QOI_ImageEncoder_Register(*ImageEncoder.QOI_ImageEncoder) As "_PB_ImageEncoder_Register@4"
  EndImport
CompilerElse
  ImportC ""
    QOI_ImageDecoder_Register(*ImageDecoder.QOI_ImageDecoder) As "_PB_ImageDecoder_Register"
    QOI_ImageEncoder_Register(*ImageEncoder.QOI_ImageEncoder) As "_PB_ImageEncoder_Register"
  EndImport
CompilerEndIf

; Define constants to use for file name encoding and pixel channel offsets.
CompilerIf #PB_Compiler_OS = #PB_OS_Windows
  CompilerIf #PB_Compiler_Unicode
    #QOI_FileName_Encoding = #PB_Unicode
  CompilerElse 
    #QOI_FileName_Encoding = #PB_Ascii
  CompilerEndIf 
  
  #QOI_OFFSET32_RED   = 2
  #QOI_OFFSET32_GREEN = 1
  #QOI_OFFSET32_BLUE  = 0
  #QOI_OFFSET32_ALPHA = 3
  
  #QOI_OFFSET24_RED   = 2
  #QOI_OFFSET24_GREEN = 1
  #QOI_OFFSET24_BLUE  = 0
CompilerElse
  #QOI_FileName_Encoding = #PB_UTF8  
  
  #QOI_OFFSET32_RED   = 0
  #QOI_OFFSET32_GREEN = 1
  #QOI_OFFSET32_BLUE  = 2
  #QOI_OFFSET32_ALPHA = 3
  
  #QOI_OFFSET24_RED   = 0
  #QOI_OFFSET24_GREEN = 1
  #QOI_OFFSET24_BLUE  = 2
CompilerEndIf

; ImagePlugin ID (QOI)
#PB_ImagePlugin_QOI = $514F49

; QOI image file signature (qoif)
#QOI_FMT_SIG = $66696F71

; QOI colorspaces - ignored in this implementation, purely for information as per spec.
#QOI_SRGB   = 0
#QOI_LINEAR = 1

#QOI_OP_INDEX  = $00 ; /* 00xxxxxx, color index */
#QOI_OP_DIFF   = $40 ; /* 01xxxxxx, difference */
#QOI_OP_LUMA   = $80 ; /* 10xxxxxx, luma difference */
#QOI_OP_RUN    = $c0 ; /* 11xxxxxx, run (repeat) */
#QOI_OP_RGB    = $fe ; /* 11111110, full 24-bit color */
#QOI_OP_RGBA   = $ff ; /* 11111111, full 32-bit color */

#QOI_MASK_2    = $c0 ; /* 11000000 */

#QOI_HEADER_SIZE = 14
#QOI_FOOTER_SIZE = 8
#QOI_PIXELS_MAX = $400000000

; Convenient access to single unsigned 8-bit chars in buffer.
Structure QOI_BUFFER
  Bytes.a[0]
EndStructure

; RGBA color channels
Structure QOI_CHANNELS
  r.a
  g.a
  b.a
  a.a
EndStructure

; RGBA color struct with union to 32-bit color value.
Structure QOI_RGBA
  StructureUnion
    Channels.QOI_CHANNELS
    Color.l
  EndStructureUnion
EndStructure

; Color hash as used in index table.
Macro QOI_COLOR_HASH(px)
  (px\Channels\r * 3 + px\Channels\g * 5 + px\Channels\b * 7 + px\Channels\a * 11)
EndMacro

; Fetch a 32-bit unsigned integer, big endian.
Macro _QOI_GetUint32BE(buffer, offset)
  ((buffer\Bytes[offset] << 24) | (buffer\Bytes[offset + 1] << 16) | (buffer\Bytes[offset + 2] << 8) | buffer\Bytes[offset + 3])
EndMacro

; Set a 32-bit unsigned integer, big endian.
Macro _QOI_SetUint32BE(buffer, offset, v)
  buffer\Bytes[offset + 0] = (v >> 24) & $ff
  buffer\Bytes[offset + 1] = (v >> 16) & $ff
  buffer\Bytes[offset + 2] = (v >>  8) & $ff
  buffer\Bytes[offset + 3] =  v        & $ff
EndMacro

;{ [ ========== DECODER ========== ]
;-[ ========== DECODER ========== ]
  ;- _QOI_Cleanup
  QOI_ProcedureI _QOI_Cleanup(*Globals.QOI_ImageDecoderGlobals)
    If *Globals\Mode = #QOI_ImageDecoder_File And *Globals\Buffer
      FreeMemory(*Globals\Buffer) : *Globals\Buffer = #Null : *Globals\Length = 0
    EndIf
  EndProcedure
  
  ;- _QOI_Check
  QOI_ProcedureI _QOI_Check(*Globals.QOI_ImageDecoderGlobals)
    Protected *qoi.QOI_BUFFER
    
    If (*Globals\Mode = #QOI_ImageDecoder_File)
      ; open file for reading
      Protected hFile = ReadFile(#PB_Any, PeekS(*Globals\Filename, -1, #QOI_FileName_Encoding))
      If (Not hFile)
        ProcedureReturn #False 
      EndIf 
      
      If (Lof(hFile) < #QOI_HEADER_SIZE)
        CloseFile(hFile)
        ProcedureReturn #False 
      EndIf 
      
      ; verify signature 
      If (ReadLong(hFile) <> #QOI_FMT_SIG)
        CloseFile(hFile)
        ProcedureReturn #False 
      EndIf 
      
      ; read the entire file 
      FileSeek(hFile, 0)
      
      *Globals\Length = Lof(hFile)
      *Globals\Buffer = AllocateMemory(*Globals\Length, #PB_Memory_NoClear)
      
      If (Not *Globals\Buffer)
        CloseFile(hFile)
        ProcedureReturn #False 
      EndIf 
      
      If (ReadData(hFile, *Globals\Buffer, *Globals\Length) <> *Globals\Length)
        _QOI_Cleanup(*Globals)
        CloseFile(hFile)
        ProcedureReturn #False 
      EndIf 
    EndIf 
    
    If (*Globals\Buffer And *Globals\Length >= #QOI_HEADER_SIZE)
      If (PeekL(*Globals\Buffer) <> #QOI_FMT_SIG)
        ProcedureReturn #False 
      EndIf 
      
      *qoi = *Globals\Buffer
      *Globals\Width = _QOI_GetUint32BE(*qoi, 4)
      *Globals\Height = _QOI_GetUint32BE(*qoi, 8)
      *Globals\OriginalDepth = *qoi\Bytes[12] * 8
      *Globals\Depth = *qoi\Bytes[12] * 8
      *Globals\Data[0] = *qoi\Bytes[13] ; colorspace, is purely informative according spec and should not change pixels are encoded.
    EndIf 
    
    If (Not *Globals\Width Or Not *Globals\Height Or Not *Globals\Depth Or Not *Globals\OriginalDepth)
      _QOI_Cleanup(*Globals)
      ProcedureReturn #False 
    EndIf 
    
    ProcedureReturn #True 
  EndProcedure
  
  ;- _QOI_Decode
  QOI_ProcedureI _QOI_Decode(*Globals.QOI_ImageDecoderGlobals, *Buffer, Pitch.l, Flags.l)
    Protected Dim index.QOI_RGBA(64)                                      ; index
    Protected pixel.QOI_RGBA                                              ; current pixel state
    Protected channels = *Globals\Depth / 8                               ; bytes per pixel
    Protected pixel_length = *Globals\Width * *Globals\Height * channels  ; number of bytes in source
    Protected *bytes.QOI_BUFFER = *Globals\Buffer                         ; source buffer
    Protected *pixels.QOI_BUFFER = *Buffer                                ; target buffer 
    Protected run = 0                                                     ; run count, when > 0 pixels will be stored again next iteration
    Protected pixel_pos = 0                                               ; current ouptput pixel 
    Protected real_pixel_pos = 0                                          ; real output pixel after optional Y reversal
    Protected chunks_length = *Globals\Length - #QOI_FOOTER_SIZE          ; length of buffer up to footer 
    Protected p = #QOI_HEADER_SIZE                                        ; soft pointer in source 
    Protected reverseY = Flags & #QOI_ImageDecoder_ReverseY               ; whether or not Y reversal should be applied 
    Protected real_line_pitch = (channels * *Globals\Width)               ; The real line pitch (channels * width)
    Protected line_pitch_padding = Pitch - real_line_pitch                ; PureBasic is rather messy, Pitch can include padding we need to ignore.
    Protected line_pitch_count = 0                                        ; variable to track when we reach the actual line pitch. 
    
    ; initialize pixel as black
    With pixel\Channels
      \r = 0
      \g = 0
      \b = 0
      \a = 255
    EndWith
    
    While (pixel_pos < pixel_length)
      If (run > 0)
        run - 1 ; output same pixel and continue.
      ElseIf (p < chunks_length)
        Protected b1 = *bytes\Bytes[p] : p + 1
        
        If (b1 = #QOI_OP_RGB) 
          ; full 24-bit color
          With pixel\Channels
            \r = *bytes\Bytes[p] : p + 1
            \g = *bytes\Bytes[p] : p + 1
            \b = *bytes\Bytes[p] : p + 1
          EndWith
        ElseIf (b1 = #QOI_OP_RGBA)
          ; full 32-bit color
          With pixel\Channels
            \r = *bytes\Bytes[p] : p + 1
            \g = *bytes\Bytes[p] : p + 1
            \b = *bytes\Bytes[p] : p + 1
            \a = *bytes\Bytes[p] : p + 1
          EndWith
        ElseIf ((b1 & #QOI_MASK_2) = #QOI_OP_INDEX)
          ; use pixel from index 
          pixel\Color = index(b1)\Color
        ElseIf ((b1 & #QOI_MASK_2) = #QOI_OP_DIFF)
          ; output pixel with a relative difference from the previous one.
          With pixel\Channels
            \r + ((b1 >> 4) & $03) - 2
            \g + ((b1 >> 2) & $03) - 2
            \b + ( b1       & $03) - 2 
          EndWith
        ElseIf ((b1 & #QOI_MASK_2) = #QOI_OP_LUMA)
          ; output pixel with a relative difference from the previous one, with the green channel as leading.
          Protected b2 = *bytes\Bytes[p] : p + 1
          Protected vg = (b1 & $3f) - 32
          
          With pixel\Channels
            \r + vg - 8 + ((b2 >> 4) & $0f)
            \g + vg
            \b + vg - 8 +  (b2       & $0f)
          EndWith
        ElseIf ((b1 & #QOI_MASK_2) = #QOI_OP_RUN)
          ; a run is encountered, repeat a pixel a number of times.
          run = (b1 & $3f)
        EndIf 
        
        ; store in index
        index(QOI_COLOR_HASH(pixel) % 64)\Color = pixel\Color
      EndIf 
      
      ; determine if PureBasic wants us to output the color with a reversed Y coordinate (the bottom is Y = 0)
      real_pixel_pos = pixel_pos
      If (reverseY)
        real_pixel_pos = (*Globals\Height - (pixel_pos / Pitch) - 1) * Pitch + (pixel_pos % Pitch)
      EndIf 
      
      ; output to PB buffer
      *pixels\Bytes[real_pixel_pos + #QOI_OFFSET32_RED]   = pixel\Channels\r
      *pixels\Bytes[real_pixel_pos + #QOI_OFFSET32_GREEN] = pixel\Channels\g
      *pixels\Bytes[real_pixel_pos + #QOI_OFFSET32_BLUE]  = pixel\Channels\b
      
      If (channels = 4)
        *pixels\Bytes[real_pixel_pos + #QOI_OFFSET32_ALPHA] = pixel\Channels\a
      EndIf 
      
      pixel_pos + channels
      
      If (line_pitch_padding)
        ; handle the situation where PureBasic has additional padding in each line,
        ; causing the line pitch in PureBasic to differ from the pitch (channels * width).
        line_pitch_count + channels
        If (line_pitch_count = real_line_pitch)
          pixel_pos + line_pitch_padding
          line_pitch_count = 0
        EndIf 
      EndIf 
    Wend 
    
    ; the reference decoder does not check for the terminating bytes 0 0 0 0 0 0 0 1
    ; so we skip that check as well. We have everything we need.
    
    ProcedureReturn #True 
  EndProcedure
  
  Procedure UseQOIImageDecoder()
    Static QOIDecoder.QOI_ImageDecoder
    Static Registered
    
    If (Not Registered)
      QOIDecoder\ID = #PB_ImagePlugin_QOI
      QOIDecoder\Check = @_QOI_Check()
      QOIDecoder\Cleanup = @_QOI_Cleanup()
      QOIDecoder\Decode = @_QOI_Decode()
      QOI_ImageDecoder_Register(QOIDecoder)
      Registered = #True 
    EndIf 
    
    ProcedureReturn Registered 
  EndProcedure
;}

;{ [ ========== ENCODER ========== ]
;-[ ========== ENCODER ========== ]
  ;- _QOI_Encode
  QOI_ProcedureI.i _QOI_Encode(*Filename, *Buffer, Width.l, Height.l, LinePitch.l, Flags.l, EncoderFlags.l, RequestedDepth.l)
    Protected Dim index.QOI_RGBA(64)              ; index
    Protected pixel.QOI_RGBA, prev_pixel.QOI_RGBA ; current and previous pixel state
    Protected *bytes.QOI_BUFFER                   ; the buffer containing the encoded qoi image
    Protected *pixels.QOI_BUFFER                  ; the PureBasic pixel buffer
    Protected max_size                            ; the maximum size of the output including header and footer
    Protected p                                   ; the soft pointer into the output array
    Protected run                                 ; the amount of times a pixel has yet to be repeated 
    Protected index_pos                           ; the position into the index
    Protected pixel_length                        ; the PureBasic pixel buffer length
    Protected pixel_pos                           ; the current position into the PureBasic pixel buffer
    Protected pixel_end                           ; the end of the PureBasic pixel buffer
    Protected channels                            ; the number of channels in the output 
    Protected reverseY                            ; whether or not the Y-coordinate should be reversed
    Protected real_pixel_pos                      ; real_pixel_pos is the translated position with optional Y-reversal
    Protected real_line_pitch                     ; The real line pitch (channels * width)
    Protected line_pitch_padding                  ; PureBasic is rather messy, LinePitch can include padding we need to ignore.
    Protected line_pitch_count                    ; variable to track when we reach the actual line pitch. 
    
    reverseY = Flags & #QOI_ImageDecoder_ReverseY
    real_line_pitch = ((RequestedDepth / 8) * Width)
    line_pitch_padding = LinePitch - real_line_pitch
    
    If (Width = 0 Or Height = 0 Or (RequestedDepth <> 24 And RequestedDepth <> 32) Or (Height >= #QOI_PIXELS_MAX / Width))
      ProcedureReturn #False ; not a valid state, cannot encode
    EndIf 
    
    channels = RequestedDepth / 8
    max_size = Width * Height * (channels + 1) + #QOI_HEADER_SIZE + #QOI_FOOTER_SIZE
    p        = 0
    *pixels  = *Buffer
    *bytes   = AllocateMemory(max_size)
    
    If (Not *bytes)
      ProcedureReturn #False 
    EndIf 
    
    PokeL(*bytes, #QOI_FMT_SIG)         : p + 4
    _QOI_SetUint32BE(*bytes, p, Width)  : p + 4
    _QOI_SetUint32BE(*bytes, p, Height) : p + 4
    *bytes\Bytes[p] = channels          : p + 1
    *bytes\Bytes[p] = #QOI_SRGB         : p + 1 ; colorspace is purely informative and does not change a thing.
    
    run = 0
    With prev_pixel\Channels
      \r = 0
      \g = 0
      \b = 0
      \a = 255
    EndWith
    
    pixel\Color = prev_pixel\Color
    
    pixel_length = Height * LinePitch
    pixel_end = pixel_length - channels
    
    While (pixel_pos < pixel_length)
      ; determine if PureBasic wants us to output the color with a reversed Y coordinate (the bottom is Y = 0)
      real_pixel_pos = pixel_pos
      If (reverseY)
        real_pixel_pos = (Height - (pixel_pos / LinePitch) - 1) * LinePitch + (pixel_pos % LinePitch)
      EndIf 
      
      With pixel\Channels
        \r = *pixels\Bytes[real_pixel_pos + #QOI_OFFSET32_RED]
        \g = *pixels\Bytes[real_pixel_pos + #QOI_OFFSET32_GREEN]
        \b = *pixels\Bytes[real_pixel_pos + #QOI_OFFSET32_BLUE]
        
        If (channels = 4)
          \a = *pixels\Bytes[real_pixel_pos + #QOI_OFFSET32_ALPHA]
        EndIf 
      EndWith
    
      If (pixel\Color = prev_pixel\Color)
        run + 1
        If (run = 62 Or pixel_pos = pixel_end)
          *bytes\Bytes[p] = #QOI_OP_RUN | (run - 1) : p + 1
          run = 0
        EndIf 
      Else 
        If (run > 0)
          *bytes\Bytes[p] = #QOI_OP_RUN | (run - 1) : p + 1
          run = 0
        EndIf 
        
        index_pos = QOI_COLOR_HASH(pixel) % 64
        
        If (index(index_pos)\Color = pixel\Color)
          *bytes\Bytes[p] = #QOI_OP_INDEX | index_pos : p + 1
        Else 
          index(index_pos)\Color = pixel\Color
          
          If (pixel\Channels\a = prev_pixel\Channels\a)
            ; check if we can store based on differences between components
            Protected vr.b = pixel\Channels\r - prev_pixel\Channels\r
            Protected vg.b = pixel\Channels\g - prev_pixel\Channels\g
            Protected vb.b = pixel\Channels\b - prev_pixel\Channels\b
            
            Protected vg_r.b = vr - vg
            Protected vg_b.b = vb - vg
            
            If (vr > -3 And vr < 2 And vg > -3 And vg < 2 And vb > -3 And vb < 2)
              ; encode as difference from previous with 2-bits per channel
              *bytes\Bytes[p] = #QOI_OP_DIFF | ((vr + 2) << 4) | ((vg + 2) << 2) | (vb + 2)
              p + 1
            ElseIf (vg_r > -9 And vg_r < 8 And vg > -33 And vg < 32 And vg_b > -9 And vg_b < 8)
              ; encode as difference from previous with the green channel leading the way
              *bytes\Bytes[p] = #QOI_OP_LUMA      | (vg   + 32) : p + 1
              *bytes\Bytes[p] = ((vg_r + 8) << 4) | (vg_b + 8)  : p + 1
            Else 
              ; encode as full RGB color
              With pixel\Channels
                *bytes\Bytes[p] = #QOI_OP_RGB : p + 1
                *bytes\Bytes[p] = \r          : p + 1
                *bytes\Bytes[p] = \g          : p + 1
                *bytes\Bytes[p] = \b          : p + 1
              EndWith
            EndIf 
          Else 
            ; encode as full RGBA color
            With pixel\Channels
              *bytes\Bytes[p] = #QOI_OP_RGBA : p + 1
              *bytes\Bytes[p] = \r           : p + 1
              *bytes\Bytes[p] = \g           : p + 1
              *bytes\Bytes[p] = \b           : p + 1
              *bytes\Bytes[p] = \a           : p + 1
            EndWith
          EndIf 
        EndIf 
      EndIf   
      
      prev_pixel\Color = pixel\Color
      
      pixel_pos + channels 
      
      If (line_pitch_padding)
        ; handle the situation where PureBasic has additional padding in each line,
        ; causing the line pitch in PureBasic to differ from the pitch (channels * width).
        line_pitch_count + channels
        If (line_pitch_count = real_line_pitch)
          pixel_pos + line_pitch_padding
          line_pitch_count = 0
        EndIf 
      EndIf 
    Wend 
    
    ; footer 
    *bytes\Bytes[p] = 0 : p + 1
    *bytes\Bytes[p] = 0 : p + 1
    *bytes\Bytes[p] = 0 : p + 1
    *bytes\Bytes[p] = 0 : p + 1
    *bytes\Bytes[p] = 0 : p + 1
    *bytes\Bytes[p] = 0 : p + 1
    *bytes\Bytes[p] = 0 : p + 1
    *bytes\Bytes[p] = 1 : p + 1
    
    If (*Filename)
      Protected hFile = CreateFile(#PB_Any, PeekS(*Filename, -1, #QOI_FileName_Encoding))
      If (Not hFile)
        FreeMemory(*bytes)
        ProcedureReturn #False 
      EndIf 
      
      Protected result = #True 
      If (WriteData(hFile, *bytes, p) <> p)
        result = #False 
      EndIf 
      
      FreeMemory(*bytes)
      CloseFile(hFile)
      
      ProcedureReturn result 
    Else
      *bytes = ReAllocateMemory(*bytes, p)
      ProcedureReturn *bytes 
    EndIf 
  EndProcedure
  
  Procedure UseQOIImageEncoder()
    Static QOIEncoder.QOI_ImageEncoder, Registered
    If Not Registered
      QOIEncoder\ID = #PB_ImagePlugin_QOI
      QOIEncoder\Encode24 = @_QOI_Encode()
      QOIEncoder\Encode32 = @_QOI_Encode()
      QOI_ImageEncoder_Register(QOIEncoder)
      Registered = #True
    EndIf
    ProcedureReturn Registered
  EndProcedure

;}
; IDE Options = PureBasic 6.00 Beta 5 - C Backend (MacOS X - arm64)
; CursorPosition = 541
; FirstLine = 522
; Folding = ---
; EnableXP