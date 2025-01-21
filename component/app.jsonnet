local kap = import 'lib/kapitan.libjsonnet';
local inv = kap.inventory();
local params = inv.parameters.exoscale_cloud_controller_manager;
local argocd = import 'lib/argocd.libjsonnet';

local app = argocd.App('exoscale-cloud-controller-manager', params.namespace);

local appPath =
  local project = std.get(std.get(app, 'spec', {}), 'project', 'syn');
  if project == 'syn' then 'apps' else 'apps-%s' % project;

{
  ['%s/exoscale-cloud-controller-manager' % appPath]: app,
}
