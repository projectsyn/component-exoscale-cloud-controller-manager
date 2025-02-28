local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';
local inv = kap.inventory();
local base_directory = inv.parameters._base_directory;
local params = inv.parameters.exoscale_cloud_controller_manager;

local isOpenShift =
  std.member([ 'openshift4', 'oke' ], inv.parameters.facts.distribution);

local rbac_manifests =
  std.parseYaml(kap.yaml_load_stream('%s/manifests/v%s/rbac.yml' % [
    base_directory,
    params.images.exoscale_cloud_controller_manager.tag,
  ]));
local ccm_manifests =
  std.parseYaml(kap.yaml_load_stream('%s/manifests/v%s/ccm.yml' % [
    base_directory,
    params.images.exoscale_cloud_controller_manager.tag,
  ]));

local secret = kube.Secret('exoscale-credentials') {
  metadata+: {
    namespace: params.namespace,
  },
  data:: {},
  stringData: {
    'api-key': params.credentials.api_key,
    'api-secret': params.credentials.api_secret,
    'api-zone': inv.parameters.facts.region,
  },
};

local patchNamespace(obj) =
  if std.objectHas(obj.metadata, 'namespace') then
    obj {
      metadata+: {
        namespace: params.namespace,
      },
    }
  else obj;

local rbac = [
  local o = patchNamespace(obj);
  if obj.kind == 'ClusterRoleBinding' then
    o {
      subjects: [
        subj {
          namespace: params.namespace,
        }
        for subj in super.subjects
      ],
    }
  else o
  for obj in rbac_manifests
];

local customRBAC = if isOpenShift then
  [
    kube.RoleBinding('ccm-hostnetwork') {
      metadata+: {
        // Required if we want to deploy this manifest during cluster
        // bootstrap.
        namespace: params.namespace,
      },
      roleRef_: kube.ClusterRole('system:openshift:scc:hostnetwork'),
      subjects: [
        {
          kind: 'ServiceAccount',
          name: std.filter(
            function(obj) obj.kind == 'Deployment', ccm_manifests
          )[0].spec.template.spec.serviceAccountName,
          namespace: params.namespace,
        },
      ],
    },
  ]
else
  [];


local ccm = [
  local o = patchNamespace(obj);
  if o.kind == 'Deployment' then
    o {
      spec+: {
        template+: {
          spec+: {
            nodeSelector: params.nodeSelector,
            tolerations+: [ {
              key: 'node.kubernetes.io/not-ready',
            } ],
            containers: [
              super.containers[0] {
                image:
                  '%(registry)s/%(repository)s:%(tag)s' %
                  params.images.exoscale_cloud_controller_manager,
              },
            ],
          },
        },
      },
    }
  else
    o
  for obj in ccm_manifests
];

local objKey(prefix, obj) =
  local sanitize(str) =
    std.asciiLower(std.strReplace(std.strReplace(str, '-', '_'), ':', '_'));
  local nsname = if std.objectHas(obj.metadata, 'namespace') then
    '%s_%s' % [ sanitize(obj.metadata.namespace), sanitize(obj.metadata.name) ]
  else
    obj.metadata.name;
  '%s_%s_%s' % [ prefix, sanitize(obj.kind), nsname ];

// NOTE(sg): We generate individual files for each object here so that we
// don't need to further process the rendered manifests to feed them to the
// OpenShift install process which requires that additional manifests are
// stored in individual files.
{
  [if params.namespace != 'kube-system' then '00_namespace']:
    kube.Namespace(params.namespace) {
      metadata+: {
        annotations+: {
          // NOTE(sg): we set this unconditionally since it doesn't matter on
          // non-OCP.
          'openshift.io/node-selector': '',
        },
      },
    },
  '01_secret': secret,
} + {
  [objKey('10_rbac', obj)]: obj
  for obj in rbac + customRBAC
} + {
  [objKey('20_ccm', obj)]: obj
  for obj in ccm
}
