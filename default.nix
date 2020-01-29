import <k8s/deploy> {

    network = {
        subnet  = "192.168.56.0/24";
        gateway = "192.168.56.1";
        dns     = [ "8.8.8.8" "8.8.4.4" ];
    };

    node0 = {
        roles = [ "loadbalancer" ];
        address = "192.168.56.10";
    };

    node1 = {
        roles = [ "master" "worker" ];
        address = "192.168.56.11";
    };

    node2 = {
        roles = [ "worker" ];
        address = "192.168.56.12";
    };

}
