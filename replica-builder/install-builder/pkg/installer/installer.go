package installer

import (
	"fmt"
	"io/fs"
	"log"
	"os"
	"path/filepath"
	"strings"

	"github.com/RHEcosystemAppEng/SaaSi/replica-builder/install-builder/pkg/config"
)

type Installer struct {
	appConfig       *config.ApplicationConfig
	installerConfig *config.InstallerConfig
}

func NewInstallerFromConfig(appConfig *config.ApplicationConfig, installerConfig *config.InstallerConfig) *Installer {
	installer := Installer{appConfig: appConfig, installerConfig: installerConfig}

	return &installer
}

func (i *Installer) BuildKustomizeInstaller() {
	for _, ns := range i.appConfig.Application.Namespaces {
		log.Printf("Creating installer for NS %s with move2kube", ns.Name)

		outputFolder := i.installerConfig.OutputFolderForNS(ns.Name)
		kustomizeFolder := i.installerConfig.BaseKustomizeFolderForNS(ns.Name)

		kustomization := filepath.Join(kustomizeFolder, config.KustomizationFile)
		os.Create(kustomization)
		AppendToFile(kustomization, "resources:")
		filepath.WalkDir(outputFolder, func(path string, d fs.DirEntry, e error) error {
			if e != nil {
				return e
			}
			if !d.IsDir() && filepath.Ext(d.Name()) == ".yaml" {
				// log.Printf("Moving %s to %s", d.Name(), kustomizeFolder)
				os.Rename(path, filepath.Join(kustomizeFolder, d.Name()))
				AppendToFile(kustomization, fmt.Sprintf("\n  - %s", d.Name()))
			}
			return nil
		})
		// RunCommand("move2kube", "plan", "--source", outputFolder, "--name", ns.Name)
		// RunCommand("move2kube", "transform", "--qa-skip", "true", "--output", i.installerConfig.InstallerFolder())
	}

	i.createKustomizeTemplate()
}

func (i *Installer) createKustomizeTemplate() {
	for _, ns := range i.appConfig.Application.Namespaces {
		log.Printf("Creating kustomize template for NS %s", ns.Name)
		templateFolder := i.installerConfig.KustomizeTemplateFolderForNS(ns.Name)

		paramsFolder := filepath.Join(templateFolder, config.ParamsFolder)
		os.Rename(i.installerConfig.TmpParamsFolderForNS(ns.Name), paramsFolder)
		secretsFolder := filepath.Join(templateFolder, config.SecretsFolder)
		os.Rename(i.installerConfig.TmpSecretsFolderForNS(ns.Name), secretsFolder)

		templateKustomization := i.installerConfig.KustomizationFileFrom(templateFolder)
		os.Create(templateKustomization)
		text := "resources:\n" +
			"  - ../base\n"
		AppendToFile(templateKustomization, text)

		text = "generatorOptions:\n" +
			"  disableNameSuffixHash: true\n" +
			"configMapGenerator:"
		AppendToFile(templateKustomization, text)
		err := filepath.WalkDir(paramsFolder,
			func(path string, d fs.DirEntry, err error) error {
				if err != nil {
					return err
				}
				if !d.IsDir() {
					configMap := strings.Replace(d.Name(), ".env", "", 1)

					log.Printf("Creating configMapGenerator for %s", configMap)
					text = "\n" +
						"- name: %s\n" +
						"  behavior: merge\n" +
						"  envs:\n" +
						"  - %s/%s"
					AppendToFile(templateKustomization, text, configMap, config.ParamsFolder, d.Name())
				}
				return nil
			})
		if err == nil {
			text := "\nsecretGenerator:"
			AppendToFile(templateKustomization, text)
			err = filepath.WalkDir(secretsFolder,
				func(path string, d fs.DirEntry, err error) error {
					if err != nil {
						return err
					}
					if !d.IsDir() {
						secret := strings.Replace(d.Name(), ".env", "", 1)
						log.Printf("Creating secretGenerator for %s", secret)
						text = "\n" +
							"- name: %s\n" +
							"  behavior: create\n" +
							"  envs:\n" +
							"  - %s/%s"
						AppendToFile(templateKustomization, text, secret, config.SecretsFolder, d.Name())
					}
					return nil
				})
			if err != nil {
				log.Fatalf("Cannot create kustomize template: %s", err)
			}
		}
	}
}
