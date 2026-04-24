# Script reading

Example script formats:

- see ~/creative/about-time/draft.org
  - L3 org headers represent stage directions
  - L4 org headers represent dialogue
    below an L4 normal text represents the dialogue text of that character
    You might see `**** BOB softly` or `**** BOB` or `**** BOB (softly)` or `**** BOB (softly, with a smile)` or `**** BOB (softly, with a smile, looking at ALICE)` -> for these are dialogue directions to the actor, but I assume we have to ignore those for yapper
- see ~/creative/about-time/draft.md
  - You might see '**BOB:**` or `BOB:` at the *start of a line only* with the dialogue on the next line(s) until the next character name or stage direction
  - stage directions always look like this: `*BEN considers this.*`

config for reading:
```
auto-assign-voices: true/false # assigns a separate voice to each character but consistently follows this
character-voices:
   BOB: "en-GB-Wavenet-B"
   ALICE: "en-GB-Wavenet-C"
   BEN: "en-GB-Wavenet-D"
read-stage-directions: true/false # whether to read stage directions or ignore them
```
