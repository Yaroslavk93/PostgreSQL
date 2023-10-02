
Vagrant.configure("2") do |config|
  config.vm.box = "ubuntu/focal64"
  config.vbguest.auto_update = false

  machines = {
    'pg-node1' => '192.168.10.10',
    'pg-node2' => '192.168.10.11',
    'pg-node3' => '192.168.10.12',
    'pg-node4' => '192.168.10.13',
    'pg-node5' => '192.168.10.14',
    'pg-node6' => '192.168.10.15',
  }

  machines.each do |name, ip|
    config.vm.define name do |machine|
      machine.vm.box = "ubuntu/focal64"
      machine.vm.hostname = name
      machine.vm.network :private_network, ip: ip

      machine.vm.provider "virtualbox" do |vb|
        if ['pg-node4', 'pg-node5', 'pg-node6'].include?(name)
          vb.memory = "8192" # 8 GB for these nodes
          vb.cpus = 2
        else
          vb.memory = "16384" # 16 GB for the other nodes
          vb.cpus = 4
        end
      end

      machine.vm.provision "shell", inline: <<-SHELL
        sudo apt-get update
        # ... Установка дополнительных пакетов и зависимостей
      SHELL
    end
  end
end
