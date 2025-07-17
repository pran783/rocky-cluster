Vagrant.configure("2") do |config|
config.vm.box = "bento/rockylinux-8"
config.vm.boot_timeout = 600
  nodes = {
    "master" => "192.168.56.180",
    "compute1" => "192.168.56.181",
    "compute2" => "192.168.56.182"
  }

  nodes.each do |hostname, ip|
    config.vm.define hostname do |node|
      node.vm.hostname = hostname
      node.vm.network "private_network", ip: ip
      node.vm.provider "virtualbox" do |vb|
        vb.memory = 2048
        vb.cpus = 2
        vb.customize ["modifyvm", :id, "--uartmode1", "disconnected"]
      end
      node.vm.provision "shell", path: "bootstrap.sh", args: [hostname]
    end
  end
end