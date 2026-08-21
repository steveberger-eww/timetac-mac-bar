import Testing
@testable import TimeTacKit

@Suite("Account locator")
struct AccountLocatorTests {
    @Test("Takes a bare account name and says nothing about the server")
    func bareName() {
        let locator = AccountLocator.parse("yourcompany")
        #expect(locator?.account == "yourcompany")
        #expect(locator?.host == nil)
    }

    @Test("Pulls account and server out of a pasted web address")
    func webAddress() {
        #expect(AccountLocator.parse("https://go.timetac.com/yourcompany")
                == AccountLocator(account: "yourcompany", host: .production))
        #expect(AccountLocator.parse("https://go-sandbox.timetac.com/yourcompany")
                == AccountLocator(account: "yourcompany", host: .sandbox))
    }

    @Test("Copes with what a browser's address bar actually hands you")
    func messyInput() {
        // Scheme-less, www-prefixed, deep path, query string, trailing whitespace.
        let expected = AccountLocator(account: "yourcompany", host: .production)
        #expect(AccountLocator.parse("go.timetac.com/yourcompany") == expected)
        #expect(AccountLocator.parse("  https://www.go.timetac.com/yourcompany/  ") == expected)
        #expect(AccountLocator.parse("https://go.timetac.com/yourcompany/tracking?tab=today") == expected)
        #expect(AccountLocator.parse("https://api.timetac.com/yourcompany") == expected)
    }

    @Test("Rejects input with no account in it")
    func rejects() {
        #expect(AccountLocator.parse("") == nil)
        #expect(AccountLocator.parse("   ") == nil)
        // A host on its own carries no account.
        #expect(AccountLocator.parse("https://go.timetac.com") == nil)
        #expect(AccountLocator.parse("https://go.timetac.com/") == nil)
        // An unknown hostname is not an account name, however much it looks like one.
        #expect(AccountLocator.parse("example.com/yourcompany") == nil)
        #expect(AccountLocator.parse("your company") == nil)
    }
}

@Suite("Company setup")
struct CompanySetupTests {
    @Test("A build's baked-in setup fills an empty configuration")
    func seedsEmpty() {
        let defaults = CompanyDefaults.Values(
            account: "yourcompany", host: .sandbox, clientID: "abc", clientSecret: "shh"
        )
        let configuration = AppConfiguration().applyingCompanyDefaults(defaults)

        #expect(configuration.account == "yourcompany")
        #expect(configuration.host == .sandbox)
        #expect(configuration.clientID == "abc")
        #expect(configuration.hasCompanySetup)
    }

    @Test("Baked-in setup never overwrites what someone has already configured")
    func leavesExistingAlone() {
        let defaults = CompanyDefaults.Values(
            account: "yourcompany", host: .sandbox, clientID: "abc", clientSecret: "shh"
        )
        let existing = AppConfiguration(account: "elsewhere", host: .production, clientID: "xyz")
        let configuration = existing.applyingCompanyDefaults(defaults)

        #expect(configuration.account == "elsewhere")
        #expect(configuration.host == .production)
        #expect(configuration.clientID == "xyz")
    }

    @Test("Company setup is complete before anyone has signed in")
    func completenessSplit() {
        let configuration = AppConfiguration(account: "yourcompany", clientID: "abc")
        // Enough to show a login screen…
        #expect(configuration.hasCompanySetup)
        // …but not enough to restore a session on its own.
        #expect(!configuration.isComplete)
    }
}
