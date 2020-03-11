let
    networks = [
        {
            name = "nikops-net";
            type = "bridge";
            virtualport = "openvswitch";
        }
    ];
in
import <k8s/cluster> {
    network = {
        subnet   = "192.168.101.0/24";
        gateway  = "192.168.101.1";
        dns      = [ "8.8.8.8" "8.8.4.4" ];
        managed  = false;
    };

    node0 = {
        roles = [ "loadbalancer" ];
        address = "192.168.101.10";
        libvirtd = {
            URI = "qemu+ssh://shen@10.128.24.26/system";
            inherit networks;
        };
    };

    node1 = {
        roles = [ "master" "worker" ];
        address = "192.168.101.11";
        libvirtd = {
            URI = "qemu+ssh://shen@10.128.24.26/system";
            inherit networks;
        };
    };

    node2 = {
        roles = [ "worker" ];
        address = "192.168.101.12";
        libvirtd = {
            URI = "qemu+ssh://shen@10.128.24.89/system";
            inherit networks;
        };
    };

    node3 = {
        roles = [ "master" ];
        address = "192.168.101.13";
        libvirtd = {
            URI = "qemu+ssh://shen@10.128.24.28/system";
            inherit networks;
        };
    };

    node4 = {
        roles = [ "master" "worker" ];
        address = "192.168.101.14";
        libvirtd = {
            inherit networks;
        };
    };

    hypervisor = "libvirtd";
}
