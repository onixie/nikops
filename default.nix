let deploy = import <k8s/deploy> ;
    as     = import <k8s/network> {
        subnet  = "192.168.56.0/24";
        gateway = "192.168.56.1";
        dns     = [ "8.8.8.8" "8.8.4.4" ];
    };

    node0 = {
        name = "kubernetes";
        address = "192.168.56.9";
    };

    node1 = {
        name = "master1";
        address = "192.168.56.10";
    };

    node2 = {
        name = "master2";
        address = "192.168.56.11";
    };

    node4 = {
        name = "master3";
        address = "192.168.56.13";
    };

    node3 = {
        name = "worker1";
        address = "192.168.56.12";
    };

    node5 = {
        name = "worker2";
        address = "192.168.56.14";
    };

    inCluster = [ node0 node1 node2 node3 node4 node5 ];

    env = {
        deployment.targetEnv             = "virtualbox";
        deployment.virtualbox.headless   = true;
        deployment.virtualbox.memorySize = 2048;
        deployment.virtualbox.vcpu       = 2;
    };

in {
    kubernetes = deploy node0 as <k8s/loadbalancer> inCluster env;
    master1    = deploy node1 as <k8s/master> inCluster env;
    master2    = deploy node2 as <k8s/master> inCluster env;
    master3    = deploy node4 as <k8s/master> inCluster env;
    worker1    = deploy node3 as <k8s/worker> inCluster env;
    worker2    = deploy node5 as <k8s/worker> inCluster env;
}
