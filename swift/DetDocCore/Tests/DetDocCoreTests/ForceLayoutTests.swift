import Foundation
import Testing
@testable import DetDocCore

private func dist(_ a: DocGraphPoint, _ b: DocGraphPoint) -> Double {
    ((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y)).squareRoot()
}

@Test func connectedNodesEndCloserThanUnconnected() {
    let ids = ["a", "b", "c", "d"]
    let edges = [DocGraphEdge("a", "b"), DocGraphEdge("c", "d")]
    let p = ForceLayout.compute(nodeIDs: ids, edges: edges)

    let avgEdge = (dist(p["a"]!, p["b"]!) + dist(p["c"]!, p["d"]!)) / 2
    let nonEdge = [dist(p["a"]!, p["c"]!), dist(p["a"]!, p["d"]!),
                   dist(p["b"]!, p["c"]!), dist(p["b"]!, p["d"]!)]
    let avgNonEdge = nonEdge.reduce(0, +) / Double(nonEdge.count)
    #expect(avgEdge < avgNonEdge)
}

@Test func layoutIsDeterministic() {
    let ids = ["a", "b", "c"]
    let edges = [DocGraphEdge("a", "b")]
    #expect(ForceLayout.compute(nodeIDs: ids, edges: edges)
            == ForceLayout.compute(nodeIDs: ids, edges: edges))
}

@Test func handlesEmptyAndSingle() {
    #expect(ForceLayout.compute(nodeIDs: [], edges: []).isEmpty)
    #expect(ForceLayout.compute(nodeIDs: ["solo"], edges: []) == ["solo": DocGraphPoint(x: 0, y: 0)])
}

@Test func sameGroupNodesClusterCloserThanCrossGroup() {
    // No links at all — only folder grouping should pull same-folder docs together.
    let ids = ["a", "b", "c", "d"]
    let groups = ["a": "G1", "b": "G1", "c": "G2", "d": "G2"]
    let p = ForceLayout.compute(nodeIDs: ids, edges: [], groups: groups)

    let within = (dist(p["a"]!, p["b"]!) + dist(p["c"]!, p["d"]!)) / 2
    let crossPairs = [dist(p["a"]!, p["c"]!), dist(p["a"]!, p["d"]!),
                      dist(p["b"]!, p["c"]!), dist(p["b"]!, p["d"]!)]
    let cross = crossPairs.reduce(0, +) / Double(crossPairs.count)
    #expect(within < cross)
}
