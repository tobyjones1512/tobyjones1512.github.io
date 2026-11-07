// Run: extract History.swift (up to "extension Library") and compile with MusicXML.swift ScoreEdit.swift Chords.swift:
// swiftc -swift-version 5 -default-isolation MainActor Hist.swift MergeCheck.swift MusicXML.swift ScoreEdit.swift Chords.swift

func bar(_ n: Int) -> PMeasure { var m = PMeasure(); m.length = 1920; m.tempo = Double(n); return m }
var base = ParsedScore(); base.measures = (0..<4).map { bar($0) }
var ours = base; ours.measures[1] = bar(10)
var theirs = base; theirs.measures[2] = bar(20); theirs.measures[1] = bar(30)
let r = ScoreMerge.merge(base: base, ours: ours, theirs: theirs, preferTheirs: false)
assert(r.conflicts == [2]); assert(r.score.measures[1].tempo == 10); assert(r.score.measures[2].tempo == 20); assert(r.score.measures[3].start == 5760)
let r2 = ScoreMerge.merge(base: base, ours: ours, theirs: theirs, preferTheirs: true)
assert(r2.score.measures[1].tempo == 30)
var h = History(); h.commits = [Commit(id:"a",parents:[],message:"",date:.now,branch:"main"),Commit(id:"b",parents:["a"],message:"",date:.now,branch:"main"),Commit(id:"c",parents:["a"],message:"",date:.now,branch:"x")]
assert(h.mergeBase("b","c") == "a"); assert(h.mergeBase("a","b") == "a")
print("ok")
