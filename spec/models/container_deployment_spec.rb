describe ContainerDeployment do
  before(:each) do
    @container_deployment = FactoryGirl.create(:container_deployment,
                                               :method_type => "non_managed",
                                               :version     => "v2",
                                               :kind        => "openshift-enterprise")
    @container_deployment.create_needed_tags

    hardware = FactoryGirl.create(:hardware)
    hardware.ipaddresses << "10.0.0.1"
    hardware.ipaddresses << "37.142.68.50"
    @container_deployment_node_with_vm_ip = FactoryGirl.create(:container_deployment_node,
                                                               :vm => FactoryGirl.create(:vm_vmware,
                                                                                         :hardware => hardware))
    hardware = FactoryGirl.create(:hardware)
    hardware.ipaddresses << "37.142.68.51"
    @container_deployment_node_with_vm_hostname = FactoryGirl.create(:container_deployment_node,
                                                                     :vm => FactoryGirl.create(:vm_vmware,
                                                                                               :hardware => hardware))
    @container_deployment_node_without_vm = FactoryGirl.create(:container_deployment_node,
                                                               :address => "10.0.0.2")

    @container_deployment_node_with_vm_ip.tag_add("node")
    @container_deployment_node_without_vm.tag_add("node")
    @container_deployment_node_with_vm_hostname.tag_add("deployment_master")

    @container_deployment.container_deployment_nodes << @container_deployment_node_with_vm_ip
    @container_deployment.container_deployment_nodes << @container_deployment_node_with_vm_hostname
    @container_deployment.container_deployment_nodes << @container_deployment_node_without_vm
    @container_deployment.create_deployment_authentication("type" => "AuthenticationAllowAll")
    @container_deployment.create_deployment_authentication("userid"     => "root",
                                                           "auth_key"   => "-----BEGIN RSA PRIVATE KEY----- exmaple -----END RSA PRIVATE KEY-----",
                                                           "public_key" => "public_key",
                                                           "type"       => "AuthPrivateKey")
  end

  it "checks generate_ansible_yaml returns correct yaml" do
    result = <<-EOS
ansible_config: "/usr/share/atomic-openshift-utils/ansible.cfg"
ansible_log_path: "/tmp/ansible.log"
ansible_inventory_path: "/tmp/inventroy.yaml"
ansible_ssh_user: root
deployment:
  hosts:
  - connect_to: 37.142.68.50
    roles:
    - node
  - connect_to: 37.142.68.51
    roles:
    - master
  - connect_to: 10.0.0.2
    roles:
    - node
  roles:
    master:
      osm_use_cockpit: 'false'
      openshift_master_identity_providers:
      - name: example_name
        login: 'true'
        challenge: 'true'
        kind: AllowAllPasswordIdentityProvider
    node: {}
version: v2
variant_version: '3.2'
variant: openshift-enterprise
   EOS
    expect(@container_deployment.generate_ansible_yaml).to eql(result)
  end

  it "generates ssh keys" do
    keys = @container_deployment.send(:generate_ssh_keys)
    expect(keys[:private_key]).to start_with("-----BEGIN RSA PRIVATE KEY-----")
    expect(keys[:public_key]).to be_truthy
  end

  context "container deployment nodes" do
    it "checks extract_public_ip_or_hostname return correct address" do
      expect(@container_deployment.extract_public_ip_or_hostname(@container_deployment.container_deployment_nodes[0])).to eql("37.142.68.50")
      expect(@container_deployment.extract_public_ip_or_hostname(@container_deployment.container_deployment_nodes[1])).to eql("37.142.68.51")
      expect(@container_deployment.extract_public_ip_or_hostname(@container_deployment.container_deployment_nodes[2])).to eql("10.0.0.2")
    end

    it "create deployment nodes works properly" do
      @container_deployment.container_deployment_nodes.destroy_all
      @container_deployment.create_deployment_nodes([{"name"  => "10.0.0.2",
                                                      "roles" => {"node" => true}},
                                                     {"name" => "37.142.68.50", "roles" => {"node" => true}},
                                                     {"name" => "37.142.68.51", "roles" => {"master"            => true,
                                                                                            "deployment_master" => true}}])
      expect(@container_deployment.container_nodes_by_role("node").count).to eql(2)
      expect(@container_deployment.container_nodes_by_role("master").count).to eql(1)
      expect(@container_deployment.container_nodes_by_role("deployment_master").count).to eql(1)
      @container_deployment.container_deployment_nodes.destroy_all
    end
  end

  context "authentication yml generation" do
    before(:each) do
      @container_deployment.authentications.destroy_all
    end
    it "parse allow all correctly" do
      authentication = FactoryGirl.create(:authentication_allow_all)
      @container_deployment.authentications << authentication
      expect(@container_deployment.identity_ansible_config_format).to eq('name'      => "example_name",
                                                                         'login'     => "true",
                                                                         'challenge' => "true",
                                                                         'kind'      => "AllowAllPasswordIdentityProvider")
    end

    it "parse github correctly" do
      authentication = FactoryGirl.create(:authentication_github)
      @container_deployment.authentications << authentication
      expect(@container_deployment.identity_ansible_config_format).to eq("name"                => "example_name",
                                                                         "login"               => "true",
                                                                         "challenge"           => "false",
                                                                         "kind"                => "GitHubIdentityProvider",
                                                                         "clientID"            => "testuser",
                                                                         "clientSecret"        => "secret",
                                                                         "githubOrganizations" => ["github_organizations"])
    end

    it "parse google correctly" do
      authentication = FactoryGirl.create(:authentication_google)
      @container_deployment.authentications << authentication
      expect(@container_deployment.identity_ansible_config_format).to eq("name"         => "example_name",
                                                                         "login"        => "true",
                                                                         "challenge"    => "false",
                                                                         "kind"         => "GoogleIdentityProvider",
                                                                         "clientID"     => "testuser",
                                                                         "clientSecret" => "secret",
                                                                         "hostedDomain" => "google_hosted_domain")
    end

    it "parse htpasswd correctly" do
      authentication = FactoryGirl.create(:authentication_htpasswd)
      @container_deployment.authentications << authentication
      expect(@container_deployment.identity_ansible_config_format).to eq("name"      => "example_name",
                                                                         "login"     => "true",
                                                                         "challenge" => "true",
                                                                         "kind"      => "HTPasswdPasswordIdentityProvider",
                                                                         "filename"  => "/etc/origin/master/htpasswd")
    end

    it "parse ldap correctly" do
      authentication = FactoryGirl.create(:authentication_ldap)
      @container_deployment.authentications << authentication
      expect(@container_deployment.identity_ansible_config_format).to eq("name" => "example_name", "login" => "true",
                                                            "challenge" => "true",
                                                            "kind" => "LDAPPasswordIdentityProvider",
                                                            "attributes" => {"id"                => ["ldap_id"],
                                                                             "email"             => ["ldap_email"],
                                                                             "name"              => ["ldap_name"],
                                                                             "preferredUsername" => ["ldap_preferred_user_name"]},
                                                            "bindDN" => "ldap_bind_dn",
                                                            "bindPassword" => "secret",
                                                            "ca" => "certificate_authority",
                                                            "insecure" => "true",
                                                            "url" => "ldap_url")
    end

    it "parse openID correctly" do
      authentication = FactoryGirl.create(:authentication_open_id)
      @container_deployment.authentications << authentication
      expect(@container_deployment.identity_ansible_config_format).to eq("name"                           => "example_name",
                                                                         "login"                          => "true",
                                                                         "challenge"                      => "false",
                                                                         "kind"                           => "OpenIDIdentityProvider",
                                                                         "clientID"                       => "testuser",
                                                                         "clientSecret"                   => "secret",
                                                                         "claims"                         => {"id"=>"open_id_sub_claim"},
                                                                         "urls"                           => {"authorize" => "open_id_authorization_endpoint",
                                                                                                              "toekn"     => "open_id_token_endpoint"},
                                                                         "openIdExtraAuthorizeParameters" => "open_id_extra_authorize_parameters",
                                                                         "openIdExtraScopes"              => ["open_id_extra_scopes"])
    end

    it "parse request header correctly" do
      authentication = FactoryGirl.create(:authentication_request_header)
      @container_deployment.authentications << authentication
      expect(@container_deployment.identity_ansible_config_format).to eq("name"                                  => "example_name",
                                                                         "login"                                 => "true",
                                                                         "challenge"                             => "true",
                                                                         "kind"                                  => "RequestHeaderIdentityProvider",
                                                                         "challengeURL"                          => "request_header_challenge_url",
                                                                         "loginURL"                              => "request_header_login_url",
                                                                         "clientCA"                              => "certificate_authority",
                                                                         "headers"                               => ["request_header_headers"],
                                                                         "requestHeaderPreferredUsernameHeaders" => ["request_header_preferred_username_headers"],
                                                                         "requestHeaderNameHeaders"              => ["request_header_name_headers"],
                                                                         "requestHeaderEmailHeaders"             => ["request_header_email_headers"])
    end
  end
end
