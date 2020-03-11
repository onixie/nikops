import <k8s/cluster> {
    network = {
        subnet   = "192.168.101.0/24";
        gateway  = "192.168.101.1";
        dns      = [ "8.8.8.8" "8.8.4.4" ];
    };

    node0 = {
        roles = [ "loadbalancer" ];
        address = "192.168.101.10";
    };

    node1 = {
        roles = [ "master" "worker" ];
        address = "192.168.101.11";
    };

    node2 = {
        roles = [ "worker" ];
        address = "192.168.101.12";
    };

    node3 = {
        roles = [ "master" ];
        address = "192.168.101.13";
    };

    node4 = {
        roles = [ "master" "worker" ];
        address = "192.168.101.14";
    };

    hypervisor = "libvirtd";
}
