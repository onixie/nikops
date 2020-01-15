{ nodes, ... }:

{
    services.kubernetes = {
        roles = ["node"];
        masterAddress = nodes.master.config.networking.hostName;
    };
}
