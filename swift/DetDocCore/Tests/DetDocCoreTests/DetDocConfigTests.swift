import Foundation
import Testing
import Yams
@testable import DetDocCore

@Test func defaultConfigHasReferenceDefaults() {
    let c = DetDocConfig.default
    #expect(c.docs.include == ["**/*.md"])
    #expect(c.docs.exclude == [".detdoc/**", "node_modules/**"])
    #expect(c.paths.deny == [".env", ".env.*", "node_modules/**", ".git/**"])
    #expect(c.validation.commands.isEmpty)
    #expect(c.agent.provider == "pi-rpc")
    #expect(c.agent.model == nil)
    #expect(c.agent.thinking == "high")
    #expect(c.worktree.keepOnFailure == true)
    #expect(c.apply.autoCommit == true)
}

@Test func emptyYAMLMapDecodesToAllDefaults() throws {
    let decoded = try YAMLDecoder().decode(DetDocConfig.self, from: "{}")
    #expect(decoded == DetDocConfig.default)
}

@Test func validationCommandsAcceptStringAndObjectShapes() throws {
    let yaml = """
    validation:
      commands:
        - npm test
        - name: Build
          run: npm run build
        - command: npm run typecheck
        - cmd: swift test
    """
    let decoded = try YAMLDecoder().decode(DetDocConfig.self, from: yaml)
    #expect(decoded.validation.commands == [
        ValidationCommand(name: "npm test", run: "npm test"),
        ValidationCommand(name: "Build", run: "npm run build"),
        ValidationCommand(name: "npm run typecheck", run: "npm run typecheck"),
        ValidationCommand(name: "swift test", run: "swift test"),
    ])
}
