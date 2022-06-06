# QoiImagePlugin

A PureBasic include-only image plugin to support the [QOI (Quite OK Image) format](https://qoiformat.org/). The QoiImagePlugin.pbi file is the only file from this repository you need to incorporate the QOI format in your projects. All you need to do is `XIncludeFile "QoiImagePlugin.pbi"` and enable the decoder and/or encoder with `UseQOIImageDecoder()` and/or `UseQOIImageEncoder()`.

- [Reference Encoder/Decoder](https://github.com/phoboslab/qoi)
- [Format Specification](https://qoiformat.org/qoi-specification.pdf)

## Reasoning for writing an include-only solution.

The decoder and encoder could have been a lot more optimized by writing a user library in C or C++. Unfortunately, that would mean a user library would have to be released for every PureBasic compiler version I want to support. Especially now the new C-backend is becoming available, the include-only solution seems to be the most viable for support on multiple versions and platforms.

Currently, there is no inline assembly in the include for the same reasoning; support for x86, x86-64, ARM on all supported operating systems would mean custom inline assembly/inline C per compiler. 

If someone wants to contribute to the repository with optimized code for each platform, I would be happy to merge it in.

## Usage

### Decoder

First enable the decoder at the earliest stage of your project's code. 

```purebasic
UseQOIImageDecoder() ; Enable decoder
```

Then use the PureBasic image library like you normally would.

```purebasic
hImage1 = LoadImage(#PB_Any, "dice.qoi")
hImage2 = CatchImage(#PB_Any, ?qoiDataLabel, ?qoiDataLabelEnd - ?qoiDataLabel)
```

### Encoder

First enable the encoder at the earliest stage of your project's code.

```purebasic
UseQOIImageEncoder() ; Enable encoder
```

Then use the PureBasic image library like you normally would. You can use the image format flag `#PB_ImagePlugin_QOI` to save an image as QOI. Only 24-bit and 32-bit modes are enabled.

```purebasic
; Save any input image as QOI. 
; Remember to enable the appropriate decoders for the input types
; Remember to enable the QOI encoder.
Procedure.i ConvertToQoi(input.s, output.s)
    Protected hInput = LoadImage(#PB_Any, input)
    If (Not hInput)
        ProcedureReturn #False
    EndIf

    Protected result = SaveImage(hInput, output, #PB_ImagePlugin_QOI)
    FreeImage(hInput)
    ProcedureReturn result 
EndProcedure

; Save any input image as QOI exported buffer. 
; Remember to enable the appropriate decoders for the input types
; Remember to enable the QOI encoder.
Procedure.i ConvertToQoiBuffer(input.s)
    Protected hInput = LoadImage(#PB_Any, input)
    If (Not hInput)
        ProcedureReturn #False
    EndIf

    protected *result = EncodeImage(hInput, #PB_ImagePlugin_QOI)
    FreeImage(hInput)
    ProcedureReturn *result
EndProcedure
```

## Test

Currently there is a rudimentary test file `Test.pb` which does some conversion testing between formats. In one phase, a directory named `test` in the same parent as `Test.pb` will be scanned for images and they will be converted, then decoded and the results will be compared to the original. 

Another phase generates a couple of random images and performs similar testing. 

## Viewer Demo

There is also a `Viewer.pb` that contains a UI application for opening any supported image format (All PB formats + QOI). This application allows you to save any opened image as QOI as well. 

## Issues

There might be issues in the encoder or decoder, let me know about them through GitHub issues or through Twitter [@BGroothedde](https://twitter.com/BGroothedde).