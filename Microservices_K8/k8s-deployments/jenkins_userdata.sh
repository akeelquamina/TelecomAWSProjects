 #!/bin/bash
          sudo yum update -y
          sudo wget -O /etc/yum.repos.d/jenkins.repo https://pkg.jenkins.io/redhat-stable/jenkins.repo
          sudo rpm --import https://pkg.jenkins.io/redhat-stable/jenkins.io-2023.key
          sudo yum upgrade -y
          sudo dnf install java-17-amazon-corretto -y
          sudo yum install git -y
          sudo yum install jenkins -y
          sudo systemctl enable jenkins
          sudo systemctl start jenkins
          sudo systemctl status jenkins
          sudo yum install docker -y
          sudo usermod -a -G docker ec2-user
          newgrp docker
          sudo yum install python3.9-pip -y
          pip3 install --user docker-compose
          sudo systemctl enable docker.service
          sudo systemctl start docker.service
          sudo usermod -aG docker jenkins
          curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
          unzip awscliv2.zip
          sudo ./aws/install
          sudo mkdir -p /var/lib/jenkins/.kube
          sudo cp /root/.kube/config /var/lib/jenkins/.kube/config
          sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube
          chmod 600 /var/lib/jenkins/.kube/config
          sudo curl -LO https://dl.k8s.io/release/v1.28.4/bin/linux/amd64/kubectl
          sudo curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"
          sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
          curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
          sudo mv /tmp/eksctl /usr/local/bin
          sudo chown -R jenkins:jenkins /var/lib/jenkins/.kube/
          sudo chmod -R 700 /var/lib/jenkins/.kube/
          sudo service jenkins restart