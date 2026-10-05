# Haider for iOS

Hide text in the motion of a noise field, on your phone.

Paused, every frame is flat static. Playing, the words are there — carried by
two counter-scrolling dot populations and by nothing in any single frame. A
screenshot carries no words. The interface is glass over the field; the field is
the content.

![icon](Haider/Assets.xcassets/AppIcon.appiconset/icon-1024.png)

## Why it is on the phone

The desktop tool makes clips. This makes them where you are. Longer term it is
the product: pick a message, pick a size, save to Photos, post it.

## Build

This is developed from a Mac with Command Line Tools only, so the build runs on
the MacBook (Xcode 26.6) over ssh:

```bash
bash tools/build-sim.sh          # sync, xcodegen, build, install, launch, screenshot
```

It generates `Haider.xcodeproj` from `project.yml` with `xcodegen`, builds for
the booted iPhone 17 Pro simulator, installs, launches, and pulls a screenshot
back to `/tmp/haider_shot.png`.

## Verify the property, not the vibe

The whole product rests on one claim: a single frame is uniform, so the mask is
invisible in a still. That is checked, not assumed:

```bash
swiftc -O Haider/MotionField.swift tools/verify_field.swift -o verify && ./verify
```

It typesets a message, composites a frame the way the shader does, and compares
the lit density inside the mask against outside it. Measured: inside `0.4956`,
outside `0.4935` — delta `0.0021`. `PASS`.

## Structure

| file | role |
| --- | --- |
| `MotionField.swift` | the noise populations, the scroll, the text mask |
| `Shaders.metal` | one compute pass: cell -> population -> ink or paper |
| `MetalCompositor.swift` | uploads the field, dispatches the pass |
| `MetalPreview.swift` | live MTKView; the compositor tracks the drawable |
| `ClipWriter.swift` | renders the field to an MP4 via AVAssetWriter |
| `Theme.swift` | the Snail palette, and the field's own inks |
| `Glass.swift` | the frost idiom — material, top-lit wash, one soft shadow |
| `ContentView.swift` | the interface, such as it is |

## Rules this code follows

Both noise populations always paint in **one** ink. Give them different colours
and `P(colour A) = mask x density`, so the mask becomes readable from the colour
proportions of a single frame and the product stops working. This is a
correctness constraint, not a style choice, and it is commented at the shader.

`speckle` is the legibility knob. At `1` every pixel decorrelates the instant the
field scrolls and a human sees flicker rather than words. 3–6 is the readable
range; the app ships 4.

## Status

Runs on the simulator: field renders, message typesets, live preview animates,
clip writes to an MP4 and saves to Photos. The QR overlay is presented as the
premium feature behind a paywall sheet; StoreKit wiring and a real QR generator
are the next step. Not yet on device.

## Credit

The on-camera noise board this is built around came from Squashy Boy's video
[AI Is Ruining the Internet](https://www.youtube.com/watch?v=EiodHbR7YdE); the
graphic in it was made by his editor @Naverino. The underlying motion illusion is
Ghost Font by Eric Lu, and the science is the SpookyBench paper. None of them
gave us code — this is the credit they are owed for the idea.

## License

Source-available, same terms as the Haider CLI. Not open source.
