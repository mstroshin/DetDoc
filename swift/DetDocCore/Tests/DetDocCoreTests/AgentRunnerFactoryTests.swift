// swift/DetDocCore/Tests/DetDocCoreTests/AgentRunnerFactoryTests.swift
import Foundation
import Testing
@testable import DetDocCore

@Test func factoryReturnsPiRunnerForDefaultProvider() {
    // Default config provider is "pi-rpc".
    #expect(AgentRunnerFactory.make(config: .default) is PiAgentRunner)
}

@Test func factoryReturnsFakeRunnerForFakeProvider() {
    var config = DetDocConfig.default
    config.agent.provider = "fake"
    #expect(AgentRunnerFactory.make(config: config) is FakeAgentRunner)
}
