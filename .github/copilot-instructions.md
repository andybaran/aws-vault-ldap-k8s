---
applyTo: "*.tf,*.hcl,*.md"
---


The goal of this project is to create an infrastructre as code demo using Terraform, HCL, AWS, EKS, and Vault with LDAP integration.  The LDAP integration is intended to demonstrate how to securely manage user access to Vault using an existing Active Directory LDAP directory.  More specifically, we need to demonstrate Vault configured with static roles that manage the password rotation of an Active Directory account.  Those credentials will then be delivered to a simple python application using Vault Protected Secrets Operator deployed in the EKS cluster. The python application needs to display the secrets delivered to it from Vault via the Vault Secrets Operator on a webpage.  Much of the code in this project has already been generated and is known to work.  We now need to focus on adding the additional functionality to complete the demo.  The code currently utilizes Terraform Stacks and your work needs to continue to do so.

When generating or suggesting code for this project, please adhere to the following guidelines:

- Follow terraform and HCL best practices for formatting and structuring code.
- Code should be clear, concise, and maintainable.
- Use comments to explain complex logic or decisions in the code.
- While security is important, avoid overcomplicating the code with excessive security measures that may hinder readability or maintainability.  This is a demo project not meant for production use.
- When suggesting changes, ensure they align with the project's goals and existing architecture.
- Provide explanations for your code suggestions to help understand the reasoning behind them.
- Do research to ensure the latest and most efficient methods are used in the code. Particularly in regards to AWS services, Terraform providers, Terraform Modules and Terraform Stacks.
- When there is conflicting information regarding best practices or implementation details, prioritize official documentation skills and plugins from HashiCorp and AWS, including the local Terraform MCP server.
- Ask me clarifying questions one by one and wait for me to answer before asking another.
- Use the model Claude Opus 4.5 when generating code for this project.
- Do not commit directly to the main branch.
- I have set the correct environment variables to log into AWS.
- If you need credentials, prompt me for them and wait for my answer.

## Workflow
- Start by doing a thorough review of the existing code.
- Then create  a ToDo list and then open a github issue for each item on the list.  
- When you are ready to work on an issue create a branch in which to do so.
- Working in parallel on multiple issues is preferred; if there are similar ToDo's or github issues, group them and work them in parallel.
- When you are done working on an issue make a PR to the main branch and close the issue.
- If subsequent issues depend on the issue you just closed, notify me and wait for me to approve a merge to the main branch.

## Resources to use for reference:
- Terraform Documentation: https://developer.hashicorp.com/terraform/docs
- HCL Documentation: https://developer.hashicorp.com/hcl
- AWS Documentation: https://docs.aws.amazon.com/
- Vault Secrets Operator: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso
- Vault Secrets Operator Protected Secrets: https://developer.hashicorp.com/vault/docs/deploy/kubernetes/vso/csi
- Vault LDAP Secrets Engine: https://developer.hashicorp.com/vault/docs/secrets/ldap
- Terraform Stacks: https://developer.hashicorp.com/terraform/language/stacks
- Terraform Stacks Organization: https://developer.hashicorp.com/validated-designs/terraform-operating-guides-adoption/organizing-resources#terraform-stacks
