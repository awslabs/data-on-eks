## Quick Start
1. (Optional) set environment variables for data storage
    ``` Shell
    export DATA_PATH=/tmp/telemetry
    ```
2. start grafana container
    ``` Shell 
    ./install.sh start
    ```
3. direct to Grafana UI
    ``` 
    http://${endpoint}:3000
    ```
4. Add your Prometheus server as a data source
    - Go to `Configuration` -> `Data Sources` -> `Add data source`
    - Select the data source you added in the `Data Source` variable at the top of the dashboard
5. stop and clean up
    ``` Shell
    ./install.sh remove
    ```
