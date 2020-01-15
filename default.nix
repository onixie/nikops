let deploy = import <k8s/deploy>;
    as     = import <k8s/network> {
      subnet = "192.168.1.0/24";
      gateway = "192.168.1.1";
      dns = [ "8.8.8.8" "8.8.4.4" ];
    };

    node1 = {
      name = "master";
      address = "192.168.1.10";
    };

    node2 = {
      name = "worker1";
      address = "192.168.1.11";
    };

    cluster = [ node1 node2 ];
in {
  master  = deploy <k8s/master> (as node1) cluster;
  worker1 = deploy <k8s/worker> (as node2) cluster;
}
