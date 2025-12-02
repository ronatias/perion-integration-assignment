// DwhAdapter.cls
// Purpose:
//  - Simulate Data Warehouse snapshot integration.
//  - Mostly successful, sometimes temporary failure.
public with sharing class DwhAdapter implements IIntegrationAdapter {

    public IntegrationResult send(IntegrationContext ctx) {
        if (Math.random() < 0.1) {
            return IntegrationResult.tempError(503, 'DWH ingestion queue full');
        }
        return IntegrationResult.success('DWH snapshot stored');
    }
}
