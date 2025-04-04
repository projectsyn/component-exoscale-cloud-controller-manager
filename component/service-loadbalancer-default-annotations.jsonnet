local esp = import 'lib/espejote.libsonnet';
local kap = import 'lib/kapitan.libjsonnet';
local kube = import 'lib/kube.libjsonnet';

local inv = kap.inventory();
local params = inv.parameters.exoscale_cloud_controller_manager;

local namespace = params.namespace;

local sa = kube.ServiceAccount('service-loadbalancer-default-annotations-manager') {
  metadata+: {
    namespace: namespace,
  },
};

local cr = kube.ClusterRole('espejote:service-loadbalancer-default-annotations') {
  rules: [
    {
      apiGroups: [ '' ],
      resources: [ 'services' ],
      verbs: [ 'get', 'list', 'watch', 'update', 'patch' ],
    },
  ],
};

local crb = kube.ClusterRoleBinding('espejote:service-loadbalancer-default-annotations') {
  roleRef_: cr,
  subjects_: [ sa ],
};

local jsonnetlib = esp.jsonnetLibrary('service-loadbalancer-default-annotations', namespace) {
  spec: {
    data: {
      'annotations.json': std.manifestJson(params.serviceLoadBalancerDefaultAnnotations),
    },
  },
};

local managedresource =
  assert std.member(inv.applications, 'espejote') : 'The serviceLoadBalancerDefaultAnnotations patch depends on espejote';
  esp.managedResource('service-loadbalancer-default-annotations', namespace) {
    metadata+: {
      annotations: {
        'syn.tools/description': |||
          This ManagedResource adds default annotations to all services with `spec.type: LoadBalancer`.
          Annotations are taken from a JsonnetLibrary with the same name.
          The JsonnetLibrary contains a file `annotations.json` with the annotations to be added.
          If an annotation is already set on the service, it will not be overridden.
        |||,
      },
    },
    spec: {
      serviceAccountRef: { name: sa.metadata.name },
      context: [
        {
          name: 'services',
          resource: {
            apiVersion: 'v1',
            kind: 'Service',
            namespace: '',
          },
        },
      ],
      triggers: [
        {
          name: 'service',
          watchContextResource: {
            name: 'services',
          },
        },
      ],
      template: importstr 'espejote-templates/service-loadbalancer-default-annotations.jsonnet',
    },
  };

if std.length(params.serviceLoadBalancerDefaultAnnotations) > 0 then
  {
    '50_service_loadbalancer_default_annotations_rbac': [ namespace, sa, cr, crb ],
    '50_service_loadbalancer_default_annotations_managedresource': [ jsonnetlib, managedresource ],
  }
else
  {}
