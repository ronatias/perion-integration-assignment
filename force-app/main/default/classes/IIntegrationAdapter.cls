// IIntegrationAdapter.cls
// Purpose:
//  - Contract for system-specific integration handlers.
//  - Keeps the engine generic; each system decides how to call its API.
public interface IIntegrationAdapter {
    IntegrationResult send(IntegrationContext ctx);
}
