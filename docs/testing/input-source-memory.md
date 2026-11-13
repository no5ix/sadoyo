# Testing Per-Application Input Source Memory

## What the automated suite proves

`./build.sh --test-suite=input-source` runs `Tests/InputSourceMemoryTests.swift`
against `InputSourceMemoryMachine`, which imports neither AppKit nor Carbon. Every
scenario is driven with application keys, input source ids and injected times, and
the assertions are the events the machine reported and the actions it asked the
service to take. Covered:

1. A new application records the source it is typing with, and switches nothing.
2. Two applications remember their sources apart.
3. Entering an application asks for its remembered source.
4. A restoration is attributed to the application it was requested for, and writes
   no other application's preference.
5. A manual change is written to the frontmost application, and to it alone.
6. An application whose remembered source is already typing is never switched, and
   visiting it twice causes no second switch.
7. Rapid switching: the abandoned request is cancelled, and its notification
   arriving late is read as our own tail and written to no application.
8. An application that cannot be named (no bundle identifier and no bundle path,
   and Sadoyo's own panels) is neither switched nor remembered, and a change made
   while it is frontmost is written nowhere.
9. An identifier-less application is keyed by its bundle path, in a namespace a
   bundle identifier cannot enter.
10. A remembered source that is no longer installed is replaced by the source that
    is typing, once, and is not asked for again.
11. A refused `TISSelectInputSource` and a restoration whose notification never
    arrives leave the stored preference intact.
12. A repeated notification of the same source is one event, so the observers
    cannot echo themselves.
13. The written map survives a rebuild of the service, in order, with its sources.
14. The map's limit evicts the least recently used application, and a stored pair
    that cannot be used is dropped on the way in rather than repaired.
15. Switching the feature off stops the watching (`shouldRun`), and switching it
    back on restores from what was written.
16. Source inspection of the service: one observer per stream, both removed and
    nilled on stop, no shell-out, the app's own bundle filtered, one debounced
    write, and the settings switch driving the gate.

The `notch` suite's `splash ttft card` run is the first token's card check:
source inspection of `NotchSplashView.swift` for the single-metric card, the P50
figure, unit and purple line, the absence of any `ttftP95` in the row of charts,
the absence of the pair's layout in the card, and that the decode, prefill and
cache cards and the collected percentiles are untouched.

## What it cannot prove, and the live checklist

The suite never calls `TISSelectInputSource`, never activates an application, and
never receives a `kTISNotifySelectedKeyboardInputSourceChanged`. What only a real
session can show: that the system accepts the select, how long the notification
takes, and what macOS's per-document switching does alongside. Install the feature
in the Features hub, switch it on in Settings, then:

1. In Chrome, switch to the Chinese input method. Switch to VS Code with the plain
   layout, and back. The method is restored in Chrome without a manual click.
2. Switch the method by hand inside VS Code. Go to Chrome and back: VS Code keeps
   the new choice, Chrome keeps its own.
3. Add a third application (Terminal). Chrome → Terminal → Chrome: Chrome restores
   its own source, and Terminal records the source it was found typing with.
4. Switch fast across four applications. No input source changes in an application
   you have already left, and no source arrives after you have moved on more than
   about two seconds later.
5. Open the Input menu and watch it while Sadoyo switches: the change lands in one
   step, not a flicker between two sources.
6. Remove an input source in System Settings while it is remembered by an
   application. The next visit to that application uses what is typing and does not
   retry every switch.
7. Quit and relaunch Sadoyo, then repeat step 1: the remembering survived.
8. Turn the feature off in Settings, switch applications: nothing moves. Turn it
   back on: the same sources come back, so nothing was deleted.
9. Turn on macOS's "Automatically switch to a document's input source" and use two
   documents in one application. Note what you see: with both features on, macOS
   switches by document and Sadoyo restores by application, and the source that
   types is the last one applied. Sadoyo does not read, change, or override that
   system setting.
10. Watch the Input menu while Sadoyo's own panel is frontmost and change the
    source: Sadoyo records nothing for itself, and attributes the change to no
    application.

Record the bundle identity (`build/stage/Sadoyo.app`, and the running process), the
Mac model, the macOS version, and the input sources installed, per
[the testing strategy](README.md).

## Known limitation, stated plainly

macOS's change notification carries no actor. A source change that Sadoyo did not
request, and that does not answer a request it abandoned, is treated as the user's
choice and credited to the frontmost application. So macOS's per-document
switching, another application's own switching, or a script changing the source
while an application is frontmost will be remembered as that application's
preference. The reverse never happens: a change is never written to an application
that is not frontmost, and never written at all when the frontmost application
cannot be named.
