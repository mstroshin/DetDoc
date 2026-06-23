import Foundation

/// Deterministic Fruchterman–Reingold layout. No RNG: nodes seed on a circle by index,
/// coincident points are separated by a fixed deterministic nudge. Same input → same output.
///
/// `groups` (nodeID → group key, e.g. parent folder) adds a soft attraction between members
/// of the same group so they cluster together. Empty `groups` → pure link layout.
public enum ForceLayout {
    /// Folder cohesion is a bit softer than a real link so explicit links still dominate.
    private static let groupCohesion = 0.6

    public static func compute(nodeIDs: [String],
                               edges: [DocGraphEdge],
                               groups: [String: String] = [:],
                               iterations: Int = 300) -> [String: DocGraphPoint] {
        let n = nodeIDs.count
        if n == 0 { return [:] }
        if n == 1 { return [nodeIDs[0]: DocGraphPoint(x: 0, y: 0)] }

        let area = Double(n) * 100_000.0
        let k = (area / Double(n)).squareRoot()          // ideal edge length
        let radius = k * Double(n) / (2 * .pi) + 1

        var pos: [String: (x: Double, y: Double)] = [:]
        for (i, id) in nodeIDs.enumerated() {
            let angle = 2 * .pi * Double(i) / Double(n)
            pos[id] = (radius * Foundation.cos(angle), radius * Foundation.sin(angle))
        }

        // Same-group pairs get a soft attraction so folders cluster. O(n²) build, fine for
        // doc-sized graphs.
        var groupPairs: [(String, String)] = []
        if !groups.isEmpty {
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let a = nodeIDs[i], b = nodeIDs[j]
                    if let ga = groups[a], let gb = groups[b], ga == gb { groupPairs.append((a, b)) }
                }
            }
        }

        var temp = k * 2                                  // max displacement, cooled each pass
        for _ in 0..<iterations {
            var disp: [String: (x: Double, y: Double)] = [:]
            for id in nodeIDs { disp[id] = (0, 0) }

            // Repulsion between every pair.
            for i in 0..<n {
                for j in (i + 1)..<n {
                    let a = nodeIDs[i], b = nodeIDs[j]
                    var dx = pos[a]!.x - pos[b]!.x
                    var dy = pos[a]!.y - pos[b]!.y
                    var d = (dx * dx + dy * dy).squareRoot()
                    if d < 0.01 { dx = 0.01 * Double(i - j); dy = 0.01; d = (dx * dx + dy * dy).squareRoot() }
                    let force = k * k / d
                    disp[a]!.x += dx / d * force; disp[a]!.y += dy / d * force
                    disp[b]!.x -= dx / d * force; disp[b]!.y -= dy / d * force
                }
            }
            // Attraction along edges.
            for e in edges {
                guard let pa = pos[e.a], let pb = pos[e.b] else { continue }
                let dx = pa.x - pb.x, dy = pa.y - pb.y
                var d = (dx * dx + dy * dy).squareRoot()
                if d < 0.01 { d = 0.01 }
                let force = d * d / k
                disp[e.a]!.x -= dx / d * force; disp[e.a]!.y -= dy / d * force
                disp[e.b]!.x += dx / d * force; disp[e.b]!.y += dy / d * force
            }
            // Same-folder cohesion: a softer attraction between co-located docs.
            for (a, b) in groupPairs {
                guard let pa = pos[a], let pb = pos[b] else { continue }
                let dx = pa.x - pb.x, dy = pa.y - pb.y
                var d = (dx * dx + dy * dy).squareRoot()
                if d < 0.01 { d = 0.01 }
                let force = d * d / k * groupCohesion
                disp[a]!.x -= dx / d * force; disp[a]!.y -= dy / d * force
                disp[b]!.x += dx / d * force; disp[b]!.y += dy / d * force
            }
            // Apply, capped by current temperature.
            for id in nodeIDs {
                let d = disp[id]!
                let len = (d.x * d.x + d.y * d.y).squareRoot()
                if len > 0 {
                    let cap = Swift.min(len, temp)
                    pos[id]!.x += d.x / len * cap
                    pos[id]!.y += d.y / len * cap
                }
            }
            temp *= 0.95
        }
        return pos.mapValues { DocGraphPoint(x: $0.x, y: $0.y) }
    }
}
