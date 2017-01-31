﻿using Elastic.Installer.Domain.Session;
using Elastic.Installer.Msi.CustomActions;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Deployment.WindowsInstaller;
using WixSharp;
using Elastic.Installer.Domain.Kibana.Model.Tasks;
using Elastic.Installer.Domain.Kibana.Model;

namespace Elastic.Installer.Msi.Kibana.CustomActions.Install
{
	public class KibanaInstallStartServiceAction : CustomAction<Kibana>
	{
		public override string Name => nameof(KibanaInstallStartServiceAction);
		public override int Order => (int)KibanaCustomActionOrder.InstallStartService;
		public override Condition Condition => Condition.NOT_Installed;
		public override Return Return => Return.check;
		public override Sequence Sequence => Sequence.InstallExecuteSequence;
		public override When When => When.After;
		public override Step Step => new Step(nameof(KibanaInstallServiceAction));
		public override Execute Execute => Execute.deferred;

		[CustomAction("KibanaStartService")]
		public static ActionResult KibanaStartService(Session session) => 
			session.Handle(() => new StartServiceTask(session.ToSetupArguments(KibanaArgumentParser.AllArguments), session.ToISession()).Execute());
	}
}
