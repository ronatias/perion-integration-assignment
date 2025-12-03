// integrationAdminApp.js
// Purpose:
//  - LWC Admin Console for the integration framework.
//  - 3 tabs:
//      * Systems: manage Integration_System_Config__c
//      * Object Mappings: manage Integration_Object_Rule__c
//      * Field Mappings: manage Integration_Field_Map_Config__c
//
// Key points:
//  - Uses simple DTOs from IntegrationAdminDTOs (no Id).
//  - Upserts in Apex are keyed by:
//      * Systems        → developerName
//      * Object Rules   → (sObjectName, systemApiName)
//      * Field Mappings → (sObjectName, systemApiName, sourceFieldAPI)
//  - LWC keeps local arrays and sends them to Apex on explicit Save.

import { LightningElement, track, wire } from 'lwc';
import getSystems from '@salesforce/apex/IntegrationAdminController.getSystems';
import saveSystems from '@salesforce/apex/IntegrationAdminController.saveSystems';
import getObjectConfigs from '@salesforce/apex/IntegrationAdminController.getObjectConfigs';
import saveObjectConfigs from '@salesforce/apex/IntegrationAdminController.saveObjectConfigs';
import getFieldMappings from '@salesforce/apex/IntegrationAdminController.getFieldMappings';
import saveFieldMappings from '@salesforce/apex/IntegrationAdminController.saveFieldMappings';
import getAvailableFields from '@salesforce/apex/IntegrationAdminController.getAvailableFields';
import getIntegratableObjects from '@salesforce/apex/IntegrationAdminController.getIntegratableObjects';

export default class IntegrationAdminApp extends LightningElement {
    // --- STATE: DATA ---

    @track systems = [];          // List<SystemConfigDTO>
    @track systemOptions = [];    // [{label, value}] for System comboboxes

    @track objectConfigs = [];    // List<ObjectConfigDTO> + rowId for UI

    @track fieldMappings = [];    // List<FieldMapDTO> + rowId for UI
    @track availableFields = [];  // [{label, value}] for source field picklist

    @track sObjectOptions = [];   // [{label, value}] from getIntegratableObjects
    @track selectedSObjectName;   // Context for Field Mappings tab
    @track selectedSystemApiName;

    // --- STATE: UI ---

    @track activeTab = 'systems'; // 'systems' | 'mappings' | 'fields'
    @track isLoading = false;
    @track errorMessage;

    // --- WIRES ---

    @wire(getSystems)
    wiredSystems({ data, error }) {
        if (data) {
            // clone
            this.systems = data.map(sys => ({ ...sys }));
            // options: label = developerName (BILLING), value = developerName
            this.systemOptions = this.systems
                .filter(sys => sys.developerName)
                .map(sys => ({
                    label: sys.developerName,
                    value: sys.developerName
                }));
        } else if (error) {
            this.errorMessage = this.extractError(error);
        }
    }

    @wire(getObjectConfigs)
    wiredConfigs({ data, error }) {
        if (data) {
            // add rowId for stable key in template
            this.objectConfigs = data.map((cfg, idx) => ({
                ...cfg,
                rowId: cfg.developerName || `obj-${idx}-${Date.now()}`
            }));
        } else if (error) {
            this.errorMessage = this.extractError(error);
        }
    }

    @wire(getIntegratableObjects)
    wiredObjects({ data, error }) {
        if (data) {
            this.sObjectOptions = data.map(o => ({
                label: o.label,
                value: o.apiName
            }));
        } else if (error) {
            this.errorMessage = this.extractError(error);
        }
    }

    // --- COMMON UTILS ---

    extractError(error) {
        if (!error) return 'Unknown error';
        if (error.body && error.body.message) return error.body.message;
        if (Array.isArray(error.body) && error.body[0] && error.body[0].message) {
            return error.body[0].message;
        }
        return JSON.stringify(error);
    }

    handleTabChange(event) {
        this.activeTab = event.target.value;
        this.errorMessage = null;
    }

    get showSystemsTab()  { return this.activeTab === 'systems'; }
    get showMappingsTab() { return this.activeTab === 'mappings'; }
    get showFieldsTab()   { return this.activeTab === 'fields'; }

    get systemsTabVariant()  { return this.showSystemsTab ? 'brand' : 'neutral'; }
    get mappingsTabVariant() { return this.showMappingsTab ? 'brand' : 'neutral'; }
    get fieldsTabVariant()   { return this.showFieldsTab ? 'brand' : 'neutral'; }

    // ===================== SYSTEMS TAB =====================

    handleSystemChange(event) {
        const idx = event.target.dataset.index;
        const field = event.target.dataset.field;
        if (idx === undefined || field === undefined) return;

        // IMPORTANT:
        //  - type="checkbox"  → use event.target.checked
        //  - type="toggle"    → ALSO use event.target.checked
        //  - others (number/text) → use event.target.value
        const type = event.target.type;
        const isBooleanInput = type === 'checkbox' || type === 'toggle';

        const rawValue = isBooleanInput ? event.target.checked : event.target.value;

        const draft = [...this.systems];
        draft[idx][field] =
            field === 'maxRetries' && rawValue !== '' && rawValue !== null
                ? Number(rawValue)
                : rawValue;
        this.systems = draft;
    }

    async handleSaveSystems() {
        this.isLoading = true;
        this.errorMessage = null;
        // eslint-disable-next-line no-console
        console.log('LWC → saveSystems payload:', JSON.stringify(this.systems));

        try {
            await saveSystems({ systems: this.systems });
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // ===================== OBJECT MAPPINGS TAB =====================

    handleObjectConfigChange(event) {
        const idx = event.target.dataset.index;
        const field = event.target.dataset.field;
        if (idx === undefined || field === undefined) return;

        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : event.target.value;

        const draft = [...this.objectConfigs];
        draft[idx][field] = value;
        this.objectConfigs = draft;
    }

    addObjectConfig() {
        const defaultSObject =
            this.sObjectOptions.length ? this.sObjectOptions[0].value : '';
        const defaultSystem =
            this.systemOptions.length ? this.systemOptions[0].value : '';

        const newRow = {
            developerName: '',
            sObjectName: defaultSObject,
            systemApiName: defaultSystem,
            triggerReason: '',
            isActive: true,
            rowId: `obj-new-${Date.now()}-${this.objectConfigs.length}`
        };

        this.objectConfigs = [...this.objectConfigs, newRow];
    }

    async handleSaveObjectConfigs() {
        this.isLoading = false; // make sure spinner is off until validation passes
        this.errorMessage = null;

        // Enforce uniqueness of (sObjectName + systemApiName) on the client side.
        const seenPairs = new Set();
        for (const cfg of this.objectConfigs) {
            if (!cfg.sObjectName || !cfg.systemApiName) {
                continue;
            }
            const key = `${cfg.sObjectName}::${cfg.systemApiName}`;
            if (seenPairs.has(key)) {
                this.errorMessage =
                    'Duplicate Object + System mapping detected. ' +
                    'Only one rule per Object + System combination is allowed.';
                return;
            }
            seenPairs.add(key);
        }

        this.isLoading = true;
        try {
            // Strip rowId before sending to Apex
            const payload = this.objectConfigs.map(cfg => ({
                developerName: cfg.developerName,
                sObjectName: cfg.sObjectName,
                systemApiName: cfg.systemApiName,
                triggerReason: cfg.triggerReason,
                isActive: cfg.isActive
            }));
            await saveObjectConfigs({ configs: payload });
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // ===================== FIELD MAPPINGS TAB =====================

    async handleEditFields(event) {
        const idx = event.target.dataset.index;
        if (idx === undefined || !this.objectConfigs[idx]) return;

        const cfg = this.objectConfigs[idx];

        this.selectedSObjectName   = cfg.sObjectName;
        this.selectedSystemApiName = cfg.systemApiName;
        this.activeTab = 'fields';
        this.isLoading = true;
        this.errorMessage = null;

        try {
            const [fields, mappings] = await Promise.all([
                getAvailableFields({ sObjectName: cfg.sObjectName }),
                getFieldMappings({
                    sObjectName: cfg.sObjectName,
                    systemApiName: cfg.systemApiName
                })
            ]);

            this.availableFields = fields.map(f => ({
                label: `${f.label} (${f.apiName})`,
                value: f.apiName
            }));

            this.fieldMappings = (mappings || []).map((fm, index) => ({
                ...fm,
                rowId: fm.developerName || `fm-${index}-${Date.now()}`
            }));
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    get isAddFieldDisabled() {
        return !this.selectedSObjectName || !this.selectedSystemApiName;
    }

    addFieldMapping() {
        if (this.isAddFieldDisabled) return;

        const newRow = {
            developerName: '',
            sObjectName: this.selectedSObjectName,
            systemApiName: this.selectedSystemApiName,
            sourceFieldAPI: '',
            targetFieldName: '',
            isRequired: false,
            dataType: 'String',
            rowId: `fm-new-${Date.now()}-${this.fieldMappings.length}`
        };

        this.fieldMappings = [...this.fieldMappings, newRow];
    }

    handleFieldMappingChange(event) {
        const idx = event.target.dataset.index;
        const field = event.target.dataset.field;
        if (idx === undefined || field === undefined) return;

        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : event.target.value;

        const draft = [...this.fieldMappings];
        draft[idx][field] = value;
        this.fieldMappings = draft;
    }

    async handleSaveFieldMappings() {
        if (this.isAddFieldDisabled) return;

        this.errorMessage = null;

        // Enforce uniqueness of SourceFieldAPI per Object + System on client side.
        const seenFields = new Set();
        for (const fm of this.fieldMappings) {
            if (!fm.sourceFieldAPI) {
                continue;
            }
            const key = fm.sourceFieldAPI;
            if (seenFields.has(key)) {
                this.errorMessage =
                    'Duplicate field mapping detected. ' +
                    'The same source field cannot be mapped more than once for the selected Object + System.';
                return;
            }
            seenFields.add(key);
        }

        this.isLoading = true;
        try {
            const payload = this.fieldMappings.map(fm => ({
                developerName: fm.developerName,
                sObjectName: fm.sObjectName,
                systemApiName: fm.systemApiName,
                sourceFieldAPI: fm.sourceFieldAPI,
                targetFieldName: fm.targetFieldName,
                isRequired: fm.isRequired,
                dataType: fm.dataType
            }));
            await saveFieldMappings({
                sObjectName: this.selectedSObjectName,
                systemApiName: this.selectedSystemApiName,
                mappings: payload
            });
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }
}
