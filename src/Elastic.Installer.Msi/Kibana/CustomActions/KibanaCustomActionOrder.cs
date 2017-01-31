﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace Elastic.Installer.Msi.Kibana.CustomActions
{
	public enum KibanaCustomActionOrder
	{
		// immediate
		LogAllTheThings = 1,

		// deferred
		InstallStopService = 2,
		InstallEnvironment = 3,
		InstallDirectories = 4,
		InstallConfiguration = 5,
		InstallPlugins = 6,
		InstallService = 7,
		InstallStartService = 8,

		RollbackEnvironment = 1,
		RollbackDirectories = 2,
		RollbackService = 3,

		UninstallService = 1,
		UninstallPlugins = 2,
		UninstallDirectories = 3,
		UninstallEnvironment = 4
	}
}
