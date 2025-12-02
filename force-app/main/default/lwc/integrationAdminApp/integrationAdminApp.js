// integrationAdminApp.js
// Purpose:
//  - LWC Admin Console for the integration framework.
//  - 3 tabs:
//      * Systems: manage Integration_System__mdt (active, retries)
//      * Object Mappings: manage Integration_Object_Config__mdt
//      * Field Mappings: manage Integration_Field_Map__mdt for a chosen (Object, System)
// Key design points:
//  - All lists (systems, objects, fields) are driven by metadata (CMDT / describe).
//  - No hard-coded SObject or System; admin chooses from dropdowns.
//  - All mutations are done on client-side copies; server calls are explicit (Save buttons).

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
    // --- STATE: DATA MODELS ---

    @track systems = [];          // List<SystemConfigDTO> for Systems tab
    @track systemOptions = [];    // Combobox options for System picklists (Object Mappings tab)

    @track objectConfigs = [];    // List<ObjectConfigDTO> for Object Mappings tab

    @track fieldMappings = [];    // List<FieldMapDTO> for Field Mappings tab
    @track availableFields = [];  // Combobox options for fields on selected SObject

    @track sObjectOptions = [];   // Combobox options for SObjects (from Integration_Enabled_Object__mdt)
    @track selectedSObjectName;   // Current object being edited in Field Mappings tab
    @track selectedSystemApiName; // Current system being edited in Field Mappings tab

    // --- STATE: UI / UX ---

    @track activeTab = 'systems'; // 'systems' | 'mappings' | 'fields'
    @track isLoading = false;     // Spinner control
    @track errorMessage;          // Last error to show in UI

    // --- WIRES: LOAD INITIAL METADATA ---

    // Systems: comes from Integration_System__mdt
    @wire(getSystems)
    wiredSystems({ data, error }) {
        if (data) {
            // Defensive clone so we can edit on client
            this.systems = JSON.parse(JSON.stringify(data));
            // Build system combobox options [{label, value}]
            this.systemOptions = this.systems.map(sys => ({
                label: sys.label,
                value: sys.developerName
            }));
        } else if (error) {
            this.errorMessage = this.extractError(error);
        }
    }

    // Object→System mappings: comes from Integration_Object_Config__mdt
    @wire(getObjectConfigs)
    wiredConfigs({ data, error }) {
        if (data) {
            this.objectConfigs = JSON.parse(JSON.stringify(data));
        } else if (error) {
            this.errorMessage = this.extractError(error);
        }
    }

    // Integratable objects: comes from Integration_Enabled_Object__mdt
    @wire(getIntegratableObjects)
    wiredObjects({ data, error }) {
        if (data) {
            // data is List<FieldOptionDTO> { label, apiName }
            this.sObjectOptions = data.map(o => ({
                label: o.label,
                value: o.apiName
            }));
        } else if (error) {
            this.errorMessage = this.extractError(error);
        }
    }

    // --- UTILITIES ---

    // Normalizes Aura / Apex errors into a simple string
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
    }

    get showSystemsTab()  { return this.activeTab === 'systems'; }
    get showMappingsTab() { return this.activeTab === 'mappings'; }
    get showFieldsTab()   { return this.activeTab === 'fields'; }

    // --- SYSTEMS TAB HANDLERS ---

    // Inline edit handler for systems table
    handleSystemChange(event) {
        const idx = event.target.dataset.index;
        const field = event.target.dataset.field;
        if (idx === undefined || field === undefined) return;

        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : event.target.value;

        // Defensive: guard against out-of-range index
        if (this.systems[idx]) {
            this.systems[idx][field] = value;
        }
    }

    // Persist systems back to Integration_System__mdt
    async handleSaveSystems() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            await saveSystems({ systems: this.systems });
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // --- OBJECT MAPPINGS TAB HANDLERS ---

    // Inline edit handler for Object→System mappings table
    handleObjectConfigChange(event) {
        const idx = event.target.dataset.index;
        const field = event.target.dataset.field;
        if (idx === undefined || field === undefined) return;

        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : event.target.value;

        if (this.objectConfigs[idx]) {
            this.objectConfigs[idx][field] = value;
        }
    }

    // Add a new (blank) Object→System mapping row
    // NOTE: We do NOT hard-code Opportunity/BILLING here.
    //       Admin chooses SObject + System from comboboxes.
    addObjectConfig() {
        // Optionally pick defaults from first options, but keep it generic.
        const defaultSObject =
            this.sObjectOptions && this.sObjectOptions.length
                ? this.sObjectOptions[0].value
                : '';

        const defaultSystem =
            this.systemOptions && this.systemOptions.length
                ? this.systemOptions[0].value
                : '';

        this.objectConfigs = [
            ...this.objectConfigs,
            {
                developerName: '',
                sObjectName: defaultSObject,   // admin can change
                systemApiName: defaultSystem,  // admin can change
                triggerReason: '',             // free text (e.g. OPP_STAGE_CONTRACTING)
                isActive: true
            }
        ];
    }

    // Persist Object→System mappings back to Integration_Object_Config__mdt
    async handleSaveObjectConfigs() {
        this.isLoading = true;
        this.errorMessage = null;
        try {
            await saveObjectConfigs({ configs: this.objectConfigs });
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // --- FIELD MAPPINGS TAB HANDLERS ---

    // Called when user clicks "Edit Fields" for a given Object→System mapping row
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

            // Transform available fields to combobox {label, value}
            this.availableFields = fields.map(f => ({
                label: `${f.label} (${f.apiName})`,
                value: f.apiName
            }));

            // Defensive clone for client-side editing
            this.fieldMappings = mappings && mappings.length
                ? JSON.parse(JSON.stringify(mappings))
                : [];
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }

    // Add a new field mapping row for the currently selected (Object, System)
    addFieldMapping() {
        if (!this.selectedSObjectName || !this.selectedSystemApiName) {
            return;
        }
        this.fieldMappings = [
            ...this.fieldMappings,
            {
                developerName: '',
                sObjectName: this.selectedSObjectName,
                systemApiName: this.selectedSystemApiName,
                sourceFieldAPI: '',
                targetFieldName: '',
                isRequired: false,
                dataType: 'String'
            }
        ];
    }

    // Inline edit handler for Field Mappings table
    handleFieldMappingChange(event) {
        const idx = event.target.dataset.index;
        const field = event.target.dataset.field;
        if (idx === undefined || field === undefined) return;

        const value = event.target.type === 'checkbox'
            ? event.target.checked
            : event.target.value;

        if (this.fieldMappings[idx]) {
            this.fieldMappings[idx][field] = value;
        }
    }

    // Persist field mappings back to Integration_Field_Map__mdt
    async handleSaveFieldMappings() {
        if (!this.selectedSObjectName || !this.selectedSystemApiName) return;

        this.isLoading = true;
        this.errorMessage = null;
        try {
            await saveFieldMappings({
                sObjectName: this.selectedSObjectName,
                systemApiName: this.selectedSystemApiName,
                mappings: this.fieldMappings
            });
        } catch (e) {
            this.errorMessage = this.extractError(e);
        } finally {
            this.isLoading = false;
        }
    }
}
