# REFERENCIA TECNICA -- FreeStyle Standalone en BTP

> **Contenido**: Template MTA completo para apps SAPUI5 FreeStyle standalone (sin CAP backend) desplegadas en BTP.
> **Fuente**: Extraido de `agents/04-fiori-ui5/system_prompt.md` para lazy-load.
> **Cuanto consultar**: Cuando se necesite crear una app UI5 FreeStyle standalone en BTP sin backend CAP.

---

## mta.yaml -- SAPUI5 FreeStyle Standalone (sin CAP)

Para apps UI5 FreeStyle standalone (sin backend CAP), usar esta estructura MTA completa:

```yaml
_schema-version: "3.3"
ID: my-ui5-app
version: 1.0.0

modules:
  - name: my-ui5-app-destination-content
    type: com.sap.application.content
    requires:
      - name: my-ui5-app-destination-service
        parameters:
          content-target: true
      - name: my-ui5-app-repo-host
        parameters:
          service-key:
            name: my-ui5-app-repo-host-key
      - name: my-ui5-app-uaa
        parameters:
          service-key:
            name: my-ui5-app-uaa-key
    parameters:
      content:
        instance:
          destinations:
            - Name: my-ui5-app_html_repo_host
              ServiceInstanceName: my-ui5-app-html5-srv
              ServiceKeyName: my-ui5-app-repo-host-key
              sap.cloud.service: my-ui5-app
            - Authentication: OAuth2UserTokenExchange
              Name: my-ui5-app_uaa
              ServiceInstanceName: my-ui5-app-xsuaa-service
              ServiceKeyName: my-ui5-app-uaa-key
              sap.cloud.service: my-ui5-app
          existing_destinations_policy: update
    build-parameters:
      no-source: true

  - name: my-ui5-app-app-content
    type: com.sap.application.content
    path: .
    requires:
      - name: my-ui5-app-repo-host
        parameters:
          content-target: true
    build-parameters:
      build-result: dist
      requires:
        - artifacts:
            - myui5app.zip
          name: myui5app
          target-path: dist/

  - name: myui5app
    type: html5
    path: .
    build-parameters:
      build-result: dist
      builder: custom
      commands:
        - npm install
        - npm run build:cf
      supported-platforms: []

resources:
  - name: my-ui5-app-destination-service
    type: org.cloudfoundry.managed-service
    parameters:
      config:
        HTML5Runtime_enabled: false
        init_data:
          instance:
            destinations:
              - Authentication: NoAuthentication
                Name: ui5
                ProxyType: Internet
                Type: HTTP
                URL: https://ui5.sap.com
            existing_destinations_policy: update
        version: 1.0.0
      service: destination
      service-name: my-ui5-app-destination-service
      service-plan: lite

  - name: my-ui5-app-uaa
    type: org.cloudfoundry.managed-service
    parameters:
      config:
        tenant-mode: dedicated
        xsappname: my-ui5-app-${org}-${space}
      path: ./xs-security.json
      service: xsuaa
      service-name: my-ui5-app-xsuaa-service
      service-plan: application

  - name: my-ui5-app-repo-host
    type: org.cloudfoundry.managed-service
    parameters:
      service: html5-apps-repo
      service-name: my-ui5-app-html5-srv
      service-plan: app-host

parameters:
  deploy_mode: html5-repo
  enable-parallel-deployments: true
```

**Diferencia vs CAP+UI:** El mta.yaml CAP+UI usa modulo anidado en `app/`. Este template standalone usa `html5-apps-repo` directamente como recurso independiente con destination-service y xsuaa propios.
